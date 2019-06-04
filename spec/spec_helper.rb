RSpec.configure do |c|
  c.mock_with :rspec
end


RSpec.shared_context 'stub script settings' do
  # Including this context creates a new settings instance before each test
  # instead of re-using a shared singleton instance.
  let(:script_settings) { PuppetX::Puppetlabs::SupportScript::Settings.new }

  before(:each) do
    allow(PuppetX::Puppetlabs::SupportScript::Settings).to receive(:instance).and_return(script_settings)
  end
end

require 'facter'
require 'puppet_x/puppetlabs/support_script/v3/puppet-enterprise-support.rb'
