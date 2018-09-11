require 'spec_helper'

require 'puppet_x/puppetlabs/support_script/v2/puppet-enterprise-support.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Support do
  subject(:support_script) { described_class.new(unit_test: true) }

  before(:each) do
    suppress_standard_output
  end

  context 'with its supporting methods' do
    it 'will validate the output directory' do
      expect(support_script.unsupported_drop_directory?('/')).to eq(true)
      expect(support_script.unsupported_drop_directory?('/tmp')).to eq(false)

      options = { dir: '/error' }
      support_script.instance_variable_set(:@options, options)
      expect { support_script.validate_output_directory }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it 'will validate the output_directory disk space' do
      options = { dir: '/tmp', filesync: true, log_age: 14 }
      support_script.instance_variable_set(:@options, options)

      expect { support_script.validate_output_directory_disk_space }.to_not raise_error
    end
  end
end
