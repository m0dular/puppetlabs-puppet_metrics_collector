require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Scope do
  context 'when initializing' do
    it 'requires a name to be passed' do
      expect { described_class.new }.to raise_error(ArgumentError,
                                                    /must be initialized with a name: parameter/)
    end

    context 'when initialized with a parent' do
      let(:parent) { described_class.new(name: 'parent_scope') }
      subject { described_class.new(parent, name: 'test_scope') }

      it 'includes its parents name if non-empty' do
        expect(subject.name).to eq('parent_scope::test_scope')
      end

      it 'excludes its parents name if empty' do
        allow(parent).to receive(:name).and_return('')

        expect(subject.name).to eq('test_scope')
      end
    end
  end

  context 'when configured with children' do
    let(:check_class) { PuppetX::Puppetlabs::SupportScript::Check }
    let(:check1) { Class.new(check_class) }
    let(:check2) { Class.new(check_class) }
    let(:check3) { Class.new(check_class) }
    let(:check4) { Class.new(check_class) }

    let(:scope1) { Class.new(described_class) }
    let(:scope2) { Class.new(described_class) }
    subject { Class.new(described_class) }

    before(:each) do
      scope1.add_child(check1, name: 'check_1')
      scope2.add_child(check2, name: 'check_2')

      subject.add_child(scope1, name: 'scope_1')
      subject.add_child(scope2, name: 'scope_2')
      subject.add_child(check3, name: 'check_3')
      subject.add_child(check4, name: 'check_4')

      [check1, check2, check3, check4].each do |check|
        # Stub `run` so it does not throw a NotImplementedError
        allow_any_instance_of(check).to receive(:run).and_return(nil)
      end
    end

    describe 'when #run is called' do
      it 'skips Checks that do not return true for suitable?' do
        allow_any_instance_of(scope1).to receive(:suitable?).and_return(true)
        allow_any_instance_of(scope2).to receive(:suitable?).and_return(true)

        allow_any_instance_of(check1).to receive(:suitable?).and_return(true)
        allow_any_instance_of(check2).to receive(:suitable?).and_return(false)
        allow_any_instance_of(check3).to receive(:suitable?).and_return(false)
        allow_any_instance_of(check4).to receive(:suitable?).and_return(true)

        expect_any_instance_of(check1).to receive(:run).and_return(nil)
        expect_any_instance_of(check2).not_to receive(:run)
        expect_any_instance_of(check3).not_to receive(:run)
        expect_any_instance_of(check4).to receive(:run).and_return(nil)

        subject.new(name: 'test_scope').run
      end

      it 'skips Checks in Scopes that do not return true for suitable?' do
        allow_any_instance_of(scope1).to receive(:suitable?).and_return(true)
        allow_any_instance_of(scope2).to receive(:suitable?).and_return(false)

        allow_any_instance_of(check1).to receive(:suitable?).and_return(true)
        allow_any_instance_of(check2).to receive(:suitable?).and_return(true)
        allow_any_instance_of(check3).to receive(:suitable?).and_return(true)

        expect_any_instance_of(check1).to receive(:run).and_return(nil)
        expect_any_instance_of(check2).not_to receive(:run)

        subject.new(name: 'test_scope').run
      end

      it 'traps errors raised by children and continues' do
        allow_any_instance_of(scope1).to receive(:suitable?).and_return(false)
        allow_any_instance_of(scope2).to receive(:suitable?).and_return(false)

        allow_any_instance_of(check3).to receive(:suitable?).and_return(true)
        allow_any_instance_of(check4).to receive(:suitable?).and_return(true)

        # TODO: Add expectation for a message logged at error level.
        allow_any_instance_of(check3).to receive(:run).and_raise(RuntimeError,
                                                                 'boom!')
        expect_any_instance_of(check4).to receive(:run).and_return(nil)

        subject.new(name: 'test_scope').run
      end
    end
  end
end
