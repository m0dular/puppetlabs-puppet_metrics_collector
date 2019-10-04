require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Runner do
  include_context 'stub script settings'

  before(:each) do
    allow(Facter).to receive(:value).with('kernel').and_return('Linux')
    allow(Facter).to receive(:value).with('identity').and_return({'privileged' => true})
    allow(Facter).to receive(:value).with('hostname').and_return('rspec')
  end

  context 'when setting up' do
    it 'populates settings.state with a path to the output directory' do
      script_settings.state.delete(:drop_directory)

      subject.setup

      expect(script_settings.state[:drop_directory]).to match(/puppet_enterprise_support/)
    end

    it 'does not create multiple output directories if setup is called twice' do
      subject.setup
      drop_directory = script_settings.state[:drop_directory]

      # Drop directory name includes the hostname
      allow(Facter).to receive(:value).with('hostname').and_return('rspec2')
      subject.setup

      expect(script_settings.state[:drop_directory]).to eq(drop_directory)
    end
  end

  context 'when executing' do
    it 'logs a failure and returns 1 if required libraries are not found' do
      allow(subject).to receive(:require)
      expect(subject).to receive(:require).with('facter').and_raise(LoadError)

      expect(script_logger).to receive(:error).with(/LoadError raised when loading facter/)

      expect(subject.run).to eq(1)
    end

    it 'logs a failure and returns 1 if executed on an unsupported platform' do
      allow(Facter).to receive(:value).with('kernel').and_return('IRIX')

      expect(script_logger).to receive(:error).with(/limited to Linux operating systems/)

      expect(subject.run).to eq(1)
    end

    it 'logs a failure and returns 1 if executed without administrative privilages' do
      allow(Facter).to receive(:value).with('identity').and_return({'privileged' => false})

      expect(script_logger).to receive(:error).with(/must be run with root privilages/)

      expect(subject.run).to eq(1)
    end

    context 'when encryption is enabled' do
      before(:each) { script_settings.configure(encrypt: true) }

      it 'logs a failure and returns 1 if no gpg executable is found' do
        allow(subject).to receive(:executable?).with('gpg2').and_return(nil)
        allow(subject).to receive(:executable?).with('gpg').and_return(nil)

        expect(script_logger).to receive(:error).with(/Could not find gpg or gpg2 on the PATH/)

        expect(subject.run).to eq(1)
      end

      it 'produces an archive that ends in .gpg' do
        allow(subject).to receive(:executable?).with('gpg2').and_return('/usr/bin/gpg2')
        allow(subject).to receive(:display)
        expect(subject).to receive(:display).with(/Output archive file:.*\.gpg$/)

        expect(subject.run).to eq(0)
      end
    end

    context 'when upload is enabled' do
      before(:each) { script_settings.configure(upload: true, ticket: '1234') }

      it 'logs a failure and returns 1 if no sftp executable is found' do
        allow(subject).to receive(:executable?).with('sftp').and_return(nil)

        expect(script_logger).to receive(:error).with(/Could not find sftp on the PATH/)

        expect(subject.run).to eq(1)
      end
    end
  end
end
