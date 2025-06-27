# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--format progress"
  t.verbose = false
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

begin
  require "tapioca/internal"
rescue LoadError
  # tapioca tasks won't be available
end

task default: %i[spec rubocop typecheck]

desc "Run all tests"
task test: :spec

desc "Run linting"
task lint: :rubocop

desc "Run type checking"
task typecheck: "sorbet:tc"

desc "Run type checking"
task rbi: "sorbet:rbi"

desc "Run all quality checks (tests, lint, typecheck)"
task ci: [:spec, :rubocop, :rbi, :typecheck]

desc "Auto-fix linting issues"
task :fix do
  sh "bundle exec rubocop --auto-correct-all"
end

namespace :sorbet do
  desc "Run Sorbet type checker"
  task :tc do
    sh "bundle exec srb tc"
  end

  desc "Update RBI files"
  task :rbi do
    sh "bundle exec tapioca gems"
  end
end
