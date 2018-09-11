require 'puppet/indirector/face'
require 'puppet/feature/base'

# Primum non nocere

Puppet::Face.define(:enterprise, '1.0.0') do
  action :support do
    summary 'Collects Puppet Enterprise Support Diagnostics'

    # See also: lib/puppet_x/puppetlabs/support_script/v2/puppet-enterprise-support.rb
    default_dir     = File.directory?('/var/tmp') ? '/var/tmp' : '/tmp'
    default_log_age = 14
    default_scope   = %w[enterprise etc log networking resources system].join(',')

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
      summary 'Include FileSync data. Requires Version 2.0'
    end

    option '--log-age DAYS' do
      summary 'Log age (in days) to collect. Defaults to: 14'
      default_to { default_log_age }
    end

    option '--scope LIST' do
      summary "Scope (comma-delimited) of diagnostics to collect. Requires Version 2.0. Defaults to: #{default_scope}"
      default_to { default_scope }
    end

    option '--ticket NUMBER' do
      summary 'Support ticket number'
      default_to { '' }
    end

    option '--v2' do
      summary 'Use Version 2.0 of this command'
    end

    when_invoked do |options|
      if Puppet.features.microsoft_windows?
        Puppet.err('This command is not implemented for Windows platforms at this time.')
        exit 1
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

      if options[:filesync] && options[:v2] != true
        Puppet.err('The filesync parameter requires the v2 parameter.')
        exit 1
      end

      if options[:log_age].to_s =~ %r{^\d+|all$}
        support_script_parameters.push("-l#{options[:log_age]}")
      else
        Puppet.err("The log-age parameter must be a number, or the string 'all'. Got: #{options[:log_age]}")
        exit 1
      end

      options_scope = options[:scope].tr(' ', '')

      if options_scope != default_scope && options[:v2] != true
        Puppet.err('The scope parameter requires the v2 parameter.')
        exit 1
      end

      if options_scope =~ %r{^(\w+)(,\w+)*$}
        options[:scope] = options_scope
      else
        Puppet.err "The scope parameter must be a comma-delimited list. Got: #{options[:scope]}"
        exit 1
      end

      unless options[:ticket] == ''
        if options[:ticket] =~ %r{^[\d\w\-]+$}
          support_script_parameters.push("-t#{options[:ticket]}")
        else
          Puppet.err "The ticket parameter may contain only numbers, letters, and dashes. Got: #{options[:ticket]}"
          exit 1
        end
      end

      if options[:v2]
        require 'puppet_x/puppetlabs/support_script/v2/puppet-enterprise-support'
        Support = PuppetX::Puppetlabs::Support.new(options)
        return
      else
        support_module = File.expand_path(File.join(File.dirname(__FILE__), '../../../..'))
        support_script = File.join(support_module, 'lib/puppet_x/puppetlabs/support_script/v1/puppet-enterprise-support.sh')
        Kernel.exec('/bin/bash', support_script, *support_script_parameters)
      end
    end
  end
end
