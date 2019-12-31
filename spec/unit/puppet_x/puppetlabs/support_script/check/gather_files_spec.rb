require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Check::GatherFiles do
  include_context 'stub script settings'

  describe('#run') do
    it 'expands globs in the copy list' do
      Dir.mktmpdir('rspec') do |test_dir|
        ['foo', 'bar', 'baz'].each do |file|
          FileUtils.touch(File.join(test_dir, file))
        end

        FileUtils.mkdir(File.join(test_dir, 'subdir'))

        ['bim', 'bop'].each do |file|
          FileUtils.touch(File.join(test_dir, 'subdir', file))
        end

        test_check = described_class.new(nil,
                                         name: 'rspec-test',
                                         files: [{from: test_dir,
                                                  copy: ['{bar,baz}',
                                                         'subdir/*'],
                                                  to: test_dir}])

        ['bar', 'baz', 'subdir/bim', 'subdir/bop'].each do |file|
          expect(test_check).to receive(:copy_drop).with(file, any_args)
        end

        test_check.run
      end
    end

    it 'logs an error and returns if no disk space is available' do
      script_settings.configure(noop: false)

      Dir.mktmpdir('rspec') do |test_dir|
        ['foo', 'bar', 'baz'].each do |file|
          FileUtils.touch(File.join(test_dir, file))
        end

        test_check = described_class.new(nil,
                                         name: 'rspec-test',
                                         files: [{from: test_dir,
                                                  copy: ['{bar,baz}'],
                                                  to: test_dir}])

        allow(test_check).to receive(:exec_return_result).with(/^df/).and_return("2048")
        allow(test_check).to receive(:exec_return_result).with(/find 'bar'/).and_return("2048")
        allow(test_check).to receive(:exec_return_result).with(/find 'baz'/).and_return("2048")

        expect(script_logger).to receive(:error).with(/Not enough free disk space/)
        expect(test_check).to receive(:copy_drop).never

        test_check.run
      end
    end
  end
end
