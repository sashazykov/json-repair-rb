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

desc 'Type-check: rbs validate + steep check'
task typecheck: %i[rbs steep]

desc 'Run benchmark/run.rb (regression baseline for JSON.repair)'
task :bench do
  ruby '-Ilib', 'benchmark/run.rb'
end

task default: %i[spec rubocop rbs steep]
