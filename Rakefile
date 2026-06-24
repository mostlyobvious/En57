# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require_relative "lib/en57/tasks"

Minitest::TestTask.create

task :format do
  system("stree write **/*.rb")
  system("sqlfluff format db")
end

task :mutate do
  system("bin/mutant run")
end

task :mutate_since do
  system("bin/mutant run --since #{ENV.fetch("MUTANT_SINCE")}")
end

task default: %i[test mutate_since]
