require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Check do
  context 'when initializing' do
    it 'requires a name to be passed' do
      expect { described_class.new }.to raise_error(ArgumentError,
                                                    /must be initialized with a name: parameter/)
    end

    context 'when initialized with a parent' do
      let(:parent) { double('parent object') }

      it 'includes its parents name if non-empty' do
        allow(parent).to receive(:name).and_return('parent_object')
        test_object = described_class.new(parent, name: 'test_object')

        expect(test_object.name).to eq('parent_object::test_object')
      end

      it 'excludes its parents name if empty' do
        allow(parent).to receive(:name).and_return('')
        test_object = described_class.new(parent, name: 'test_object')

        expect(test_object.name).to eq('test_object')
      end
    end
  end
end
