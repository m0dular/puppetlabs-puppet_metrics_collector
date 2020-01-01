# Internal gem source needed for beaker-pe-large-environments.
# VPN access required.
source ENV['GEM_SOURCE'] || 'https://artifactory.delivery.puppetlabs.net/artifactory/api/gems/rubygems/'

group :test do
  gem 'rake', '~> 12.2'
  gem 'puppet', ENV['PUPPET_VERSION'] || '~> 5.5'
  gem "rspec", "~> 3.4"
  gem 'metadata-json-lint', '~> 2.0'
end

group :acceptance do
  gem 'beaker', '~> 4.0'
  gem 'beaker-pe', '~> 2.0'
  gem 'scooter', '~> 4.3'
  unless ENV.key?('GEM_SKIP_INTERNAL')
    gem 'beaker-pe-large-environments', '~> 0.3.3'
  end
end

if File.exists? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end
