require 'puppet/indirector/face'
require 'puppet/feature/base'

require 'open3'
require 'timeout'

# Primum non nocere

Puppet::Face.define(:enterprise, '1.0.0') do
  action :support do
    summary 'Collects Puppet Enterprise Support Diagnostics'

    # See also: lib/puppet_x/puppetlabs/support_script/v3/puppet-enterprise-support.rb

    default_dir     = File.directory?('/var/tmp') ? '/var/tmp' : '/tmp'
    default_log_age = 14

    supported_platforms = %w[redhat debian suse]

    option '--classifier' do
      summary 'Include Classifier data'
    end

    option '--dir DIRECTORY' do
      summary "Output directory. Defaults to: #{default_dir}"
      default_to { default_dir }
    end

    option '--encrypt' do
      summary 'Encrypt output using GPG'
    end

    option '--filesync' do
      summary 'Include FileSync data. Requires the --v3 parameter'
    end

    option '--log-age DAYS' do
      summary "Log age (in days) to collect. Defaults to: #{default_log_age}"
      default_to { default_log_age }
    end

    option '--ticket NUMBER' do
      summary 'Support ticket number'
    end

    option '--upload' do
      summary 'Upload to Puppet Support via SFTP. Requires the --ticket and --v3 parameters'
    end

    option '--upload-disable-host-key-check' do
     summary 'Disable SFTP Host Key Check. Requires the --upload parameter'
    end

    option '--upload-key FILE' do
      summary 'Key for SFTP. Requires the --upload parameter'
    end

    option '--upload-user USER' do
      summary 'User for SFTP. Requires the --upload parameter'
    end

    option '--v3' do
      summary 'Use Version 3.0 of this command (experimental)'
    end

    option '--enable LIST' do
      summary 'Comma-delimited list of scopes or checks to enable. Requires the --v3 parameter.'

      before_action do |_, _, options|
        if options.key?(:enable)
          # Copied from Ruby's OptionParser handler for Array values
          options[:enable] = options[:enable].split(',').collect {|ss| ss unless ss.empty?}
        end
      end
    end

    option '--disable LIST' do
      summary 'Comma-delimited list of scopes or checks to disable. Requires the --v3 parameter.'

      before_action do |_, arg, options|
        if options.key?(:disable)
          options[:disable] = options[:disable].split(',').collect {|ss| ss unless ss.empty?}
        end
      end
    end

    option '--only LIST' do
      summary 'Comma-delimited list of of scopes or checks to run, disabling all others. Requires the --v3 parameter.'

      before_action do |_, arg, options|
        if options.key?(:only)
          options[:only] = options[:only].split(',').collect {|ss| ss unless ss.empty?}
        end
      end
    end

    option '--list' do
      summary 'List available scopes and checks that can be passed to --enable, --disable, or --only. Requires the --v3 parameter.'
    end

    when_invoked do |options|
      support_module = File.expand_path(File.join(File.dirname(__FILE__), '../../../..'))

      if Puppet.features.microsoft_windows?
        support_script = File.join(support_module, 'lib/puppet_x/puppetlabs/support_script/v1/puppet-enterprise-support.ps1')
        begin
          Open3.popen2e('powershell.exe', '-File', support_script) do |_i, oe, t|
            begin
              Timeout.timeout(120) do
                puts oe.readline until oe.eof?
              end
            rescue Timeout::Error
              Process.kill('KILL', t.pid)
              Puppet.err('The powershell command timed out.')
              exit 1
            end
          end
        rescue => e
          Puppet.err("The powershell command returned: #{e.message}")
          exit 1
        end
        exit 0
      end

      os_family = `/opt/puppetlabs/puppet/bin/facter os.family`.chomp.strip
      unless supported_platforms.include? os_family.downcase
        Puppet.err("This command is not implemented for #{os_family} platforms at this time.")
        exit 1
      end

      support_script_parameters = []

      if options[:classifier]
        support_script_parameters.push('-c')
      end

      unless options[:dir] == ''
        support_script_parameters.push("-d#{options[:dir]}")
      end

      if options[:encrypt]
        support_script_parameters.push('-e')
      end

      if options[:filesync] && options[:v3] != true
        Puppet.err('The filesync parameter requires the --v3 parameter.')
        exit 1
      end

      if options[:log_age].to_s =~ %r{^\d+|all$}
        support_script_parameters.push("-l#{options[:log_age]}")
      else
        Puppet.err("The log-age parameter must be a number, or the string 'all'. Got: #{options[:log_age]}")
        exit 1
      end

      if options.key?(:ticket)
        if options[:ticket] =~ %r{^[\d\w\-]+$}
          support_script_parameters.push("-t#{options[:ticket]}")
        else
          Puppet.err "The ticket parameter may contain only numbers, letters, and dashes. Got: #{options[:ticket]}"
          exit 1
        end
      end

      if options[:upload] && (options[:v3] != true)
        Puppet.err('The upload parameter requires the --v3 parameter.')
        exit 1
      end

      [:enable, :disable, :only, :list].each do |opt|
        if options.key?(opt) && (options[:v3] != true)
          Puppet.err('The --%{opt} parameter requires the --v3 parameter.' %
                     {opt: opt})
          exit 1
        end
      end

      if options[:v3]
        require 'puppet_x/puppetlabs/support_script/v3/puppet-enterprise-support'
        PuppetX::Puppetlabs::SupportScript::Settings.instance.configure(**options)
        PuppetX::Puppetlabs::SupportScript::Settings.instance.log.add_logger(PuppetX::Puppetlabs::SupportScript::LogManager.console_logger)
        support = PuppetX::Puppetlabs::SupportScript::Runner.new
        support.add_child(PuppetX::Puppetlabs::SupportScript::Scope::Base, name: '')

        return support.run
      else
        support_script = File.join(support_module, 'lib/puppet_x/puppetlabs/support_script/v1/puppet-enterprise-support.sh')
        Kernel.exec('/bin/bash', support_script, *support_script_parameters)
      end
    end
  end
end
