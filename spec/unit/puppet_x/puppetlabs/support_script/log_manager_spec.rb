require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::LogManager do
  it 'only accepts children of class logger' do
    expect { subject.add_logger('string') }.to raise_error ArgumentError,
      "An instance of Logger must be passed. Got a value of type String."
  end

  Logger::Severity.constants.each do |level|
    method_name = level.to_s.downcase.to_sym

    it "implements a method for #{method_name.inspect}" do
      expect(subject.respond_to?(method_name)).to be(true)
    end
  end

  context 'when loggers have been added' do
    let(:logfile_1) { StringIO.new }
    let(:logger_1) { Logger.new(logfile_1) }
    let(:logfile_2) { StringIO.new }
    let(:logger_2) { Logger.new(logfile_2) }

    before(:each) do
      subject.add_logger(logger_1)
      subject.add_logger(logger_2)
    end

    it 'filters messages by log level' do
      logger_1.level = Logger::WARN
      logger_2.level = Logger::INFO

      expect(logger_1).not_to receive(:add).and_call_original
      expect(logger_2).to receive(:add).and_call_original

      subject.info('hello')

      expect(logfile_1.string).to be_empty
      expect(logfile_2.string).to match('hello')
    end

    it 'calls blocks that produce messages once per log statement' do
      message = 'something blew up'
      exception = double('some exception',
                          message: message)

      expect(exception).to receive(:message).once

      subject.error { exception.message }

      expect(logfile_1.string).to match(message)
      expect(logfile_2.string).to match(message)
    end
  end
end
