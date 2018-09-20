# Internal gem source needed for beaker-pe-large-environments.
# VPN access required.
source ENV['GEM_SOURCE'] || 'https://artifactory.delivery.puppetlabs.net/artifactory/api/gems/rubygems/'

group :test do
  gem "rake", ">= 10.1"
  gem "beaker", "~> 4.0"
  gem "beaker-abs", "~> 0.5"
  gem "beaker-pe", "~> 2.0"
  gem "scooter", "~> 4.3"
  gem "beaker-pe-large-environments", "~> 0.3.3"
  gem "puppet", ENV['PUPPET_VERSION'] || "~> 5.3"
  gem "rspec", "~> 3.4"
  gem "rspec-puppet", '~> 2.0'
  gem "puppetlabs_spec_helper"
  gem "metadata-json-lint"
  gem "rspec-puppet-facts"
  gem 'rubocop', '0.42.0'
  gem 'simplecov', '>= 0.11.0'
  gem 'simplecov-console'
end

if File.exists? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end
