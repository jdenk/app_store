# encoding: utf-8

require 'open-uri'
require 'csv'
require 'gooddata'
require './user_hierarchies/lib/user_hierarchies'

module GoodData::Bricks
  class HierarchyBrick < GoodData::Bricks::Brick
    def version
      "0.0.1"
    end

    def call(params)
      hierarchy_filepath = params['hierarchy_filepath']
      config = params['config']
      output_fields = params['output_fields'] || []
      hierarchy_type = params['hierarchy_type']
      symbolized_config = config.symbolize_keys
      user_hierarchy = GoodData::UserHierarchies::UserHierarchy.read_from_csv(hierarchy_filepath, symbolized_config)
      binding.pry
      results = case hierarchy_type
      when 'fixed_level'
        fixed_level_hierarchy(user_hierarchy, output_fields)
      when 'subordinates_closure'
        subordinates_closure(user_hierarchy, output_fields)
      when 'subordinates_closure_tuples'
        subordinates_closure_tuples(user_hierarchy, output_fields)
      end
      file = 'hierarchy_out.csv'
      CSV.open(file, 'w') do |csv|
        results.each { |r| csv << r }
      end
      (params['gdc_files_to_upload'] ||= []) << {:path => file}
    end

    def subordinates_closure(user_hierarchy, output_fields)
      user_hierarchy.users.map do |u|
        output_fields.map { |f| u.send(f) } + u.all_subordinates_with_self.map {|x| x[user_hierarchy.hashing_id]}
      end
    end

    def subordinates_closure_tuples(user_hierarchy, output_fields)
      results = user_hierarchy.users.mapcat { |u| u.all_subordinates_with_self.map{ |s| [u[user_hierarchy.hashing_id], s[user_hierarchy.hashing_id]] } }
      results.unshift(['user_id', 'subordinate_id'])
      results
    end

    def fixed_level_hierarchy(user_hierarchy, output_fields)
      boss = user_hierarchy.users.select { |x| x.has_manager? == false }
      fail 'There has to be just one top of the hierarchy (ie, boss that does not have bosses)' if boss.count != 1
      fail 'Each user has to have at most one boss otherwise levels cannot be assigned properly' if user_hierarchy.users.any? {|u| u.managers.count > 1}

      GoodData::UserHierarchies::UserHierarchy.crawl(boss, 1) { |u, l, m| u.level = l }

      levels = user_hierarchy.users.reduce(0) { |a, e| [a, e.level].max }
      headers = Range.new(1, levels).to_a.map { |i| "level_#{i}" } + ['level'] + output_fields

      results = user_hierarchy.users.map do |user|
        user.all_managers.rjust(levels, user).reverse.map(&:id) + [user.level] + output_fields.map { |f| user.send(f) }
      end
      results.unshift(headers)
      results
    end
  end
end
