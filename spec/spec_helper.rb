require 'logger'
require 'stringio'
require 'tmpdir'
require 'fileutils'


RSpec.configure do |c|
  c.mock_with :rspec
end

RSpec.shared_context 'stub script settings' do
  # Including this context creates a new settings instance before each test
  # instead of re-using a shared singleton instance. A logger that stores
  # data in a StringIO instance is also configured. The `noop` option is
  # also set to true in the default configuration so that external commands
  # triggered by unit tests are not executed.
  let(:script_settings) { PuppetX::Puppetlabs::SupportScript::Settings.new }
  let(:script_log) { StringIO.new }
  let(:script_logger) do
    logger = Logger.new(script_log)
    logger.level = Logger::DEBUG
    logger
  end
  let(:temp_drop_dir) { Dir.mktmpdir }


  before(:each) do
    allow(PuppetX::Puppetlabs::SupportScript::Settings).to receive(:instance).and_return(script_settings)
    script_settings.log.add_logger(script_logger)
    script_settings.configure(noop: true)
    script_settings.state[:drop_directory] = temp_drop_dir
  end

  after(:each) do
    script_logger.close
    FileUtils.remove_entry_secure(temp_drop_dir, force: true)
  end
end


require 'facter'
require 'puppet_x/puppetlabs/support_script/v3/puppet-enterprise-support.rb'
