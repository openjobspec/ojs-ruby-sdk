# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Generate YARD documentation"
task :docs do
  sh "yard doc"
end

task default: :spec
