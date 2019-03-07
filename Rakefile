require 'puppetlabs_spec_helper/rake_tasks'
require 'metadata-json-lint/rake_task'

task :metadata do
  sh "metadata-json-lint metadata.json --no-strict-license"
end

desc "Run syntax, lint, and spec tests."
task :test => [
  :spec,
  :metadata,
]
