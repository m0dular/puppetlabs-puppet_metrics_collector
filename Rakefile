require 'metadata-json-lint/rake_task'
require 'rspec/core/rake_task'

task :default do
  exec('rake', '-T')
end

RSpec::Core::RakeTask.new(:spec)

desc 'Run lint, and spec tests.'
task :test => [
  :spec,
  :metadata_lint,
]
