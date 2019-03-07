# Internal gem source needed for beaker-pe-large-environments.
# VPN access required.
source ENV['GEM_SOURCE'] || 'https://artifactory.delivery.puppetlabs.net/artifactory/api/gems/rubygems/'

group :test do
  gem 'rake', '~> 12.2'
  gem "beaker", "~> 4.0"
  gem "beaker-abs", "~> 0.5"
  gem "beaker-pe", "~> 2.0"
  gem "scooter", "~> 4.3"
  gem "beaker-pe-large-environments", "~> 0.3.3"
  gem 'puppet', ENV['PUPPET_VERSION'] || '~> 5.5'
  gem "rspec", "~> 3.4"
  gem 'rspec-puppet', '~> 2.3'
  gem 'puppetlabs_spec_helper', '~> 2.9'
  gem 'metadata-json-lint', '~> 2.0'
end

if File.exists? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end
