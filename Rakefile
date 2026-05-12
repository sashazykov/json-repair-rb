# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

desc 'Validate RBS signatures in sig/'
task :rbs do
  sh 'bundle exec rbs validate'
end

desc 'Run Steep type check against sig/'
task :steep do
  sh 'bundle exec steep check'
end

task default: %i[spec rubocop rbs steep]
