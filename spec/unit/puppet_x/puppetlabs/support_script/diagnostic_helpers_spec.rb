require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::DiagnosticHelpers do
  include_context 'stub script settings'

  class DiagnosticUser
    include PuppetX::Puppetlabs::SupportScript::Configable
    include PuppetX::Puppetlabs::SupportScript::DiagnosticHelpers

    def initialize
      initialize_configable
    end
  end

  subject { DiagnosticUser.new }

  describe '#exec_return_result' do
    it 'logs errors and returns an empty string' do
      allow(Facter::Core::Execution).to \
        receive(:execute).and_raise(Facter::Core::Execution::ExecutionFailure)

      expect(script_logger).to \
        receive(:error).with(%r{command failed: /bin/foo with error:.*ExecutionFailure})

      result = subject.exec_return_result('/bin/foo')

      expect(result).to be_empty
    end
  end

  describe '#exec_return_status' do
    it 'log errors and returns false if a command fails' do
      allow(Facter::Core::Execution).to \
        receive(:execute).and_raise(Facter::Core::Execution::ExecutionFailure)

      expect(script_logger).to \
        receive(:error).with(%r{command failed: /bin/foo with error:.*ExecutionFailure})

      result = subject.exec_return_status('/bin/foo')

      expect(result).to be(false)
    end
  end

  describe '#exec_or_fail' do
    it 'raises an error if a command fails' do
      expect { subject.exec_or_fail('false') }.to \
        raise_error(Facter::Core::Execution::ExecutionFailure,
                    %r{command failed: false})
    end
  end

  describe '#exec_drop' do
    it 'logs a message and returns false if a command is not executable' do
      allow(script_logger).to receive(:debug)
      expect(script_logger).to \
        receive(:debug).with(%r{command not found: /does/not/exist})

      result = subject.exec_drop('/does/not/exist', '/tmp', 'output')

      expect(result).to be(false)
    end
  end

  describe '#data_drop' do
  end

  describe '#copy_drop' do
    it 'logs a message and returns false if the source file is not readable' do
      allow(script_logger).to receive(:debug)
      expect(script_logger).to \
        receive(:debug).with(%r{source not readable: /does/not/exist})

      result = subject.copy_drop('/does/not/exist', '/tmp')

      expect(result).to be(false)
    end
  end

  describe '#copy_drop_mtime' do
    it 'logs a message and returns false if the source file is not readable' do
      allow(script_logger).to receive(:debug)
      expect(script_logger).to \
        receive(:debug).with(%r{source not readable: /does/not/exist})

      result = subject.copy_drop_mtime('/does/not/exist', '/tmp', 14)

      expect(result).to be(false)
    end
  end
end
