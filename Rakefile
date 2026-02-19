# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run tests with coverage enforcement"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task[:spec].invoke
end

desc "Generate YARD documentation"
task :docs do
  sh "yard doc"
end

task default: :spec
