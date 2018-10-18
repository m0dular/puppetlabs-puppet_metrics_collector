require 'spec_helper'

require 'puppet_x/puppetlabs/support_script/v3/puppet-enterprise-support.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Support do
  options = { log_age: 14, scope: '' }
  subject(:support_script) { described_class.new(options) }

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
      options = { dir: '/tmp', log_age: 14, filesync: true }
      support_script.instance_variable_set(:@options, options)
      expect { support_script.validate_output_directory_disk_space }.to_not raise_error
    end

    it 'will blacklist keys in a json hash' do
      options = { dir: '/tmp', log_age: 14, filesync: true }
      settings = '{ "username": "public", "password": "private" }'
      blacklist = ['password']
      result = support_script.pretty_json(settings, blacklist)
      expect(result).to include('public')
      expect(result).not_to include('private')
    end

    it 'will blacklist keys in an json array of hashes' do
      options = { dir: '/tmp', log_age: 14, filesync: true }
      settings = '[{ "username": "public", "password": "private" }]'
      blacklist = ['password']
      result = support_script.pretty_json(settings, blacklist)
      expect(result).to include('public')
      expect(result).not_to include('private')
    end
  end
end
