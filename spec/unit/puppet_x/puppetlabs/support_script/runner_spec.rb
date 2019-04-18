require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Runner do
  include_context 'stub script settings'

  context 'when executing' do
    before(:each) do
      allow(Facter).to receive(:value).with('kernel').and_return('Linux')
      allow(Facter).to receive(:value).with('identity').and_return({'privileged' => true})
    end

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
  end
end
