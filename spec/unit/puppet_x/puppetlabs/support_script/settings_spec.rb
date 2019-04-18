require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Settings do
  context 'when initializing' do
    [:noop, :encrypt, :upload, :upload_disable_host_key_check,
     :z_do_not_delete_drop_directory].each do |setting|
      it "requires #{setting.inspect} to be a Boolean" do
        expect { subject.configure(setting => 'yes') }.to \
          raise_error(ArgumentError,
                      /must be set to true or false\. Got a value of type String/)
      end
    end

    [:only, :enable, :disable].each do |setting|
      it "requires #{setting.inspect} to be of type Array" do
        expect { subject.configure(setting => 'foo') }.to \
          raise_error(ArgumentError,
                      /must be set to an Array value\. Got a value of type String/)
      end
    end

    it 'ensures ticket names only contain allowed characters' do
      expect { subject.configure(ticket: 'invalid because spaces') }.to \
        raise_error(ArgumentError,
                    /may contain only numbers, letters, underscores, and dashes/)
    end

    it 'ensures log_age is a string of digets or "all"' do
      expect { subject.configure(log_age: 'allthelogs') }.to \
        raise_error(ArgumentError,
                    /must be a number, or the string "all"/)
    end
  end

  context 'when validating' do
    it 'validates that dir points to an existing directory' do
      subject.configure(dir: '/does/not/exist')

      expect { subject.validate }.to \
        raise_error(RuntimeError,
                    /not an existing directory/)
    end

    context 'when upload is enabled' do
      before(:each) { subject.configure(upload: true) }

      it 'requires ticket to be set if upload is enabled' do
        # ticket defaults to an empty string: ''

        expect { subject.validate }.to \
          raise_error(RuntimeError,
                      /requires a value to be specified for the ticket setting/)
      end

      it 'validates that upload_key points to a readable file' do
        subject.configure(upload_key: '/does/not/exist', ticket: '12345')
        expect { subject.validate }.to \
          raise_error(RuntimeError,
                      /not readable or does not exist/)
      end
    end
  end
end
