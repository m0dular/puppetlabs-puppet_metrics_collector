require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Scope do
  include_context 'stub script settings'

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
        allow_any_instance_of(check2).to receive(:suitable?).and_return(false)
        allow_any_instance_of(check3).to receive(:suitable?).and_return(false)

        expect_any_instance_of(check2).not_to receive(:run)
        expect_any_instance_of(check3).not_to receive(:run)

        subject.new(name: 'test_scope').run
      end

      it 'skips Checks in Scopes that do not return true for suitable?' do
        allow_any_instance_of(scope2).to receive(:suitable?).and_return(false)

        expect_any_instance_of(check2).not_to receive(:run)

        subject.new(name: 'test_scope').run
      end

      it 'skips Checks that do not return true for enabled?' do
        allow_any_instance_of(check2).to receive(:enabled?).and_return(false)
        allow_any_instance_of(check3).to receive(:enabled?).and_return(false)

        expect_any_instance_of(check2).not_to receive(:run)
        expect_any_instance_of(check3).not_to receive(:run)

        subject.new(name: 'test_scope').run
      end

      it 'skips Checks in Scopes that do not return true for enabled?' do
        allow_any_instance_of(scope2).to receive(:enabled?).and_return(false)

        expect_any_instance_of(check2).not_to receive(:run)

        subject.new(name: 'test_scope').run
      end

      it 'traps errors raised by children and continues' do
        allow_any_instance_of(check3).to receive(:run).and_raise(RuntimeError,
                                                                 'boom!')
        expect_any_instance_of(check4).to receive(:run).and_return(nil)
        expect(script_logger).to receive(:error).and_call_original

        subject.new(name: 'test_scope').run

        expect(script_log.string).to match(/RuntimeError raised during test_scope::check_3/)
      end

      it 'logs time consumed by running children' do
        expect_any_instance_of(check4).to receive(:run) { ::Kernel.sleep(0.05) }

        subject.new(name: 'test_scope').run

        expect(script_log.string).to match(/finished evaluation of test_scope::check_4 in 0\.05\d seconds/)
      end

      context 'when children are enabled or disabled by settings' do
        it 'only runs checks that match the :only settings' do
          script_settings.configure(only: ['test_scope::scope_1',
                                           'test_scope::check_3'])

          expect_any_instance_of(check1).to receive(:run)
          expect_any_instance_of(check2).not_to receive(:run)
          expect_any_instance_of(check3).to receive(:run)
          expect_any_instance_of(check4).not_to receive(:run)

          subject.new(name: 'test_scope').run
        end

        it 'does not enable disabled checks unless explicitly listed in :only' do
          script_settings.configure(only: ['test_scope::scope_1',
                                           'test_scope::scope_2::check_2'])

          [check1, check2].each do |klass|
            klass.class_eval do
              def setup(**options)
                @enabled = false
              end
            end
          end

          expect_any_instance_of(check1).not_to receive(:run)

          subject.new(name: 'test_scope').run
        end

        it 'enables disabled checks if listed in :enable' do
          script_settings.configure(enable: ['test_scope::scope_1::check_1',
                                             'test_scope::check_3'])

          [scope1, check3].each do |klass|
            klass.class_eval do
              def setup(**options)
                @enabled = false
              end
            end
          end

          expect_any_instance_of(check1).to receive(:run)
          expect_any_instance_of(check3).to receive(:run)

          subject.new(name: 'test_scope').run
        end

        it 'does not apply :enable to siblings of a disabled scope' do
          check5 = Class.new(check_class)

          scope1.add_child(check5, name: 'check_5')
          scope1.class_eval do
            def setup(**options)
              @enabled = false
            end
          end

          script_settings.configure(enable: ['test_scope::scope_1::check_1'])

          expect_any_instance_of(check1).to receive(:run)
          expect_any_instance_of(check5).not_to receive(:run)

          subject.new(name: 'test_scope').run
        end

        it 'combines the effects of :only and :enable' do
          script_settings.configure(only: ['test_scope::scope_1'],
                                    enable: ['test_scope::scope_2::check_2'])

          expect_any_instance_of(check1).to receive(:run)
          expect_any_instance_of(check2).to receive(:run)

          subject.new(name: 'test_scope').run
        end

        it 'combines the effects of :only, :enable, and :disable' do
          script_settings.configure(only: ['test_scope::scope_1'],
                                    enable: ['test_scope::scope_2::check_2'],
                                    disable: ['test_scope::scope_1::check_1',
                                              'test_scope::scope_2'])

          expect_any_instance_of(check1).not_to receive(:run)
          expect_any_instance_of(check2).not_to receive(:run)

          subject.new(name: 'test_scope').run
        end
      end
    end
  end
end
