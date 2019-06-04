require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Settings do
  context 'when initializing' do
    [:only, :enable, :disable].each do |setting|
      it "requires #{setting.inspect} to be of type Array" do
        expect{ subject.configure(setting => 'foo') }.to \
          raise_error(ArgumentError,
                      /must be set to an Array value. Got a value of type String/)
      end
    end
  end
end
