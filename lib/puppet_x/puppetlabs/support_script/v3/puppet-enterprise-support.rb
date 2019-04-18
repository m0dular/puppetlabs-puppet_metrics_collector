#!/opt/puppetlabs/puppet/bin/ruby

require 'json'
require 'tempfile'
require 'forwardable'
require 'logger'

# Test nodes do not meet the minimum system requirements for tune to optimize.
if ENV['BEAKER_TESTING']
  ENV['TEST_CPU'] = '8'
  ENV['TEST_RAM'] = '16384'
end


module PuppetX
module Puppetlabs
# Diagnostic tools for Puppet Enterprise
#
# This module contains components for running diagnostic checks on Puppet
# Enterprise installations.
module SupportScript
  VERSION = '3.0.0.beta3'.freeze

  # Manages one or more Logger instances
  #
  # Instances of this class wrap one or more instances of Logger and direct
  # logged messages to each as appropriate. Instances of this class provide
  # a method for each level in the stdlib `Logger::Severity` module, usually:
  #
  #   - `debug`
  #   - `info`
  #   - `warn`
  #   - `error`
  #   - `fatal`
  #   - `unknown`
  class LogManager
    def initialize
      @loggers = []
    end

    # Add a Logger instance to this manager
    #
    # @param logger [Logger] The logger to add.
    # @return [void]
    def add_logger(logger)
      unless logger.is_a?(::Logger)
        raise ArgumentError, 'An instance of Logger must be passed. Got a value of type %{class}.' %
          {class: logger.class}
      end

      @loggers.push(logger)
    end

    # Remove a Logger instance from this manager
    #
    # @param logger [Logger] The logger to add.
    # @return [void]
    def remove_logger(logger)
      @loggers.delete(logger)
    end

    ::Logger::Severity.constants.each do |name|
      method_name = name.to_s.downcase.to_sym
      level = ::Logger::Severity.const_get(name)

      define_method(method_name) do |message = nil, &block|
        # If a block was passed, ignore the message.
        message = nil unless block.nil?

        @loggers.each do |logger|
          next unless logger.level <= level
          message ||= block.call unless block.nil?

          logger.send(method_name, message)
        end
      end
    end
  end

  # Holds configuration and state shared by other objects
  #
  # Classes that need access to state managed by the Settings class should
  # include the {Configable} module, which provides access to a singleton
  # instance shared by all objects.
  class Settings
    attr_reader :log
    attr_accessor :settings

    def self.instance
      @instance ||= new
    end

    def initialize
      @log = LogManager.new
      @settings = {dir: File.directory?('/var/tmp') ? '/var/tmp' : '/tmp',
                   log_age: 14,
                   noop: false,
                   encrypt: false,
                   ticket: '',
                   upload: false,
                   upload_disable_host_key_check: false,
                   z_do_not_delete_drop_directory: false,

                   enable: [],
                   disable: [],
                   only: [],

                   # TODO: Take this out of settings.
                   version: VERSION,

                   # TODO: Deprecate and replace these with Scope classes.
                   scope: %w[enterprise etc log networking resources system].product([true]).to_h,
                   # TODO: Deprecate and replace these with Check classes
                   #       that default to disabled.
                   classifier: false,
                   filesync: false}
    end

    # Update configuration of the settings object
    #
    # @param options [Hash] a hash of options to merge into the existing
    #   configuration.
    #
    # @raise [ArgumentError] if a configuration option is invalid.
    #
    # @return [void]
    def configure(**options)
      options.each do |key, value|
        v = case key
            when :enable, :disable, :only
              unless value.is_a?(Array)
                raise ArgumentError, 'The %{key} option must be set to an Array value. Got a value of type %{class}.' %
                  {key: key,
                   class: value.class}
              end
            when :noop, :encrypt, :upload, :upload_disable_host_key_check, :z_do_not_delete_drop_directory
              unless [true, false].include?(value)
                raise ArgumentError, 'The %{key} option must be set to true or false. Got a value of type %{class}.' %
                  {key: key,
                   class: value.class}
              end
            when :log_age
              unless value.to_s.match(%r{\A\d+|all\Z})
                raise ArgumentError, 'The log_age option must be a number, or the string "all". Got %{value}' %
                  {value: value}
              end

              (value.to_s == 'all') ? 999 : value.to_i
            when :scope
              (value.to_s == '') ? {}  : Hash[value.split(',').product([true])]
            when :ticket
              unless value.match(%r{\A[\d\w\-]+\Z})
                raise ArgumentError, 'The ticket option may contain only numbers, letters, underscores, and dashes. Got %{value}' %
                  {value: value}
              end
            end

        @settings[key] = v || value
      end
    end
  end

  # Mix-in module for accessing shared settings and state
  #
  # Including the `Configable` module in a class provides access to a shared
  # state object returned by {Settings.instance}. Including the `Configable`
  # module also defines helper methods to access various components of the
  # `Settings` instance as if they were local instance variables.
  module Configable
    extend Forwardable

    def_delegators :@config, :log
    def_delegators :@config, :settings

    def initialize_configable
      @config = Settings.instance
    end
  end

  # A restricting tag for diagnostics
  #
  # A confine instance  may be initialized with with a logical check and
  # resolves the check on demand to a `true` or `false` value.
  class Confine
    include Configable

    attr_accessor :fact, :values

    # Create a new confine instance
    #
    # @param fact [Symbol] Name of the fact
    # @param values [Array] One or more values to match against. They can be
    #   any type that provides a `===` method.
    # @param block [Proc] Alternatively a block can be supplied as a check.
    #   The fact value will be passed as the argument to the block. If the
    #   block returns true then the fact will be enabled, otherwise it will
    #   be disabled.
    def initialize(fact = nil, *values, &block)
      initialize_configable

      raise ArgumentError, "The fact name must be provided" unless fact or block_given?
      if values.empty? and not block_given?
        raise ArgumentError, "One or more values or a block must be provided"
      end

      @fact = fact
      @values = values
      @block = block
    end

    def to_s
      return @block.to_s if @block
      return "'%s' '%s'" % [@fact, @values.join(",")]
    end

    # Convert a value to a canonical form
    #
    # This method is used by {true?} to normalize strings and symbol values
    # prior to comparing them via `===`.
    def normalize(value)
      value = value.to_s if value.is_a?(Symbol)
      value = value.downcase if value.is_a?(String)
      value
    end

    # Evaluate the fact, returning true or false.
    def true?
      if @block and not @fact then
        begin
          return !! @block.call
        rescue StandardError => e
          log.error("%{exception_class} raised during Confine: %{message}\n\t%{backtrace}" %
                    {exception_class: e.class,
                     message: e.message,
                     backtrace: e.backtrace.join("\n\t")})
          return false
        end
      end

      unless fact = Facter[@fact]
        log.warn('Confine requested undefined fact named: %{fact}' %
                 {fact: @fact})
        return false
      end
      value = normalize(fact.value)

      return false if value.nil?

      if @block then
        begin
          return !! @block.call(value)
        rescue StandardError => e
          log.error("%{exception_class} raised during Confine: %{message}\n\t%{backtrace}" %
                    {exception_class: e.class,
                     message: e.message,
                     backtrace: e.backtrace.join("\n\t")})
          return false
        end
      end

      @values.any? { |v| normalize(v) === value }
    end
  end

  # Mix-in module for declaring and evaluating confines
  #
  # Including this module in another class allows instances of that class
  # to declare {Confine} instances which are then evaluated with a call to
  # the {suitable?} method. The module also provides a simple enable/disable
  # switch that can be set by calling {#enabled=} and checked by calling
  # {#enabled?}
  module Confinable
    # Initalizes object state used by the Confinable module
    #
    # This method should be called from the `initialize` method of any class
    # that includes the `Confinable` module.
    #
    # @return [void]
    def initialize_confinable
      @confines = []
      @enabled = true
    end

    # Sets the conditions for this instance to be used.
    #
    # This method accepts multiple forms of arguments. Each call to this method
    # adds a new {Confine} instance that must pass in order for {suitable?} to
    # return `true`.
    #
    # @return [void]
    #
    # @overload confine(confines)
    #   Confine a fact to a specific fact value or values. This form takes a
    #   hash of fact names and values. Every fact must match the values given
    #   for that fact, otherwise this resolution will not be considered
    #   suitable. The values given for a fact can be an array, in which case
    #   the value of the fact must be in the array for it to match.
    #
    #   @param [Hash{String,Symbol=>String,Array<String>}] confines set of facts
    #     identified by the hash keys whose fact value must match the
    #     argument value.
    #
    #   @example Confining to a single value
    #       confine :kernel => 'Linux'
    #
    #   @example Confining to multiple values
    #       confine :osfamily => ['RedHat', 'SuSE']
    #
    # @overload confine(confines, &block)
    #   Confine to logic in a block with the value of a specified fact yielded
    #   to the block.
    #
    #   @param [String,Symbol] confines the fact name whose value should be
    #     yielded to the block
    #   @param [Proc] block determines suitability. If the block evaluates to
    #     `false` or `nil` then the confined object will not be evaluated.
    #
    #   @yield [value] the value of the fact identified by `confines`
    #
    #   @example Confine to a host with an ipaddress in a specific subnet
    #       confine :ipaddress do |addr|
    #         require 'ipaddr'
    #         IPAddr.new('192.168.0.0/16').include? addr
    #       end
    #
    # @overload confine(&block)
    #   Confine to a block. The object will be evaluated only if the block
    #   evaluates to something other than `false` or `nil`.
    #
    #   @param [Proc] block determines suitability. If the block
    #     evaluates to `false` or `nil` then the confined object will not be
    #     evaluated.
    #
    #   @example Confine to systems with a specific file
    #       confine { File.exist? '/bin/foo' }
    def confine(confines = nil, &block)
      case confines
      when Hash
        confines.each do |fact, values|
          @confines.push Confine.new(fact, *values)
        end
      else
        if block
          if confines
            @confines.push Confine.new(confines, &block)
          else
            @confines.push Confine.new(&block)
          end
        else
        end
      end
    end

    # Check all conditions defined for the confined object
    #
    # Checks each condition defined through a call to {#confine}.
    #
    # @return [false] if any condition evaluates to `false`.
    # @return [true] all conditions evalute to `true` or no conditions
    #   were defined.
    def suitable?
      @confines.all? { |confine| confine.true? }
    end

    # Toggle the enabled status of the confined object
    #
    # @param value [true, false]
    # @return [void]
    def enabled=(value)
      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        raise ArgumentError, 'The value of enabled must be set to true or false. Got a value of type %{class}.' %
          {class: value.class}
      end

      @enabled=value
    end

    # Check the enabled status of the confined object
    #
    # @return [true, false]
    def enabled?
      @enabled
    end
  end

  # Base class for diagnostic logic
  #
  # Instances of classes inheriting from `Check` represent diagnostics to
  # be executed. Subclasses may define a {#setup} method that can use
  # {Confinable#confine} to constrain when checks are executed. All subclasses
  # must define a {#run} method that executes the diagnostic.
  #
  # @abstract
  class Check
    include Configable
    include Confinable

    # Initialize a new check
    #
    # @note This method should not be overriden by child classes. Override
    #   the #{setup} method instead.
    # @return [void]
    def initialize(parent = nil, **options)
      initialize_configable
      initialize_confinable
      @parent = parent
      @name = options[:name]

      setup(**options)

      if @name.nil?
        raise ArgumentError, '%{class} must be initialized with a name: parameter.' %
          {class: self.class.name}
      end
    end

    # Return a string representing the name of this check
    #
    # If initialized with a parent object, the return value of calling
    # `name` on the parent is pre-pended as a namespace.
    #
    # @return [String]
    def name
      return @resolved_name if defined?(@resolved_name)

      @resolved_name = if @parent.nil? || @parent.name.empty?
                         @name
                       else
                         [@parent.name, @name].join('::')
                       end

      @resolved_name.freeze
    end

    # Initialize variables and logic used by the check
    #
    # @param [Hash] options a hash of configuration options that can be used
    #   to initialize the check.
    # @return [void]
    def setup(**options)
    end

    # Execute the diagnostic represented by the check
    #
    # @return [void]
    def run
      raise NotImplementedError, 'A subclass of Check must provide a run method.'
    end
  end

  # Base class for grouping and managing diagnostics
  #
  # Instances of classes inheriting from `Scope` managage the configuration
  # and execution of a setion of children, which can be {Check} objects or
  # other `Scope` objects. Subclasses may define a {#setup} method that can use
  # {Confinable#confine} to constrain when the scope executes.
  class Scope
    include Configable
    include Confinable

    # Data for initializing children
    #
    # @return [Array<Array(Class, Hash)>]
    def self.child_specs
      @child_specs ||= []
    end

    # Add a child to be initialized by instances of this scope
    #
    # @param [Class] klass the class from which the child should be
    #   initialized.
    # @param [Hash] options a hash of options to pass when initializing
    #   the child.
    # @return [void]
    def self.add_child(klass, **options)
      child_specs.push([klass, options])
    end

    # Initialize a new scope
    #
    # @note This method should not be overriden by child classes. Override
    #   the #{setup} method instead.
    # @return [void]
    def initialize(parent = nil, **options)
      initialize_configable
      initialize_confinable
      @parent = parent
      @name = options[:name]

      setup(**options)
      if @name.nil?
        raise ArgumentError, '%{class} must be initialized with a name: parameter.' %
          {class: self.class.name}
      end

      initialize_children
    end

    # Return a string representing the name of this scope
    #
    # If initialized with a parent object, the return value of calling
    # `name` on the parent is pre-pended as a namespace.
    #
    # @return [String]
    def name
      return @resolved_name if defined?(@resolved_name)

      @resolved_name = if @parent.nil? || @parent.name.empty?
                         @name
                       else
                         [@parent.name, @name].join('::')
                       end

      @resolved_name.freeze
    end

    # Execute run logic for suitable children
    #
    # This method loops over all child instances and calls `run` on each
    # instance for which {Confinable#suitable?} returns `true`.
    #
    # @return [void]
    def run
      @children.each do |child|
        next unless child.enabled? && child.suitable?
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
        log.info('starting evaluation of %{name}' %
                 {name: child.name})

        begin
          child.run
        rescue => e
          log.error("%{exception_class} raised during %{name}: %{message}\n\t%{backtrace}" %
                    {exception_class: e.class,
                     name: child.name,
                     message: e.message,
                     backtrace: e.backtrace.join("\n\t")})
        end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)
        log.debug('finished evaluation of %{name} in %<time>.3f seconds' %
                  {name: child.name,
                   time: (end_time - start_time)})
      end
    end

    # Initialize variables and logic used by the scope
    #
    # @param [Hash] options a hash of configuration options that can be used
    #   to initialize the scope.
    # @return [void]
    def setup(**options)
    end

    private

    def initialize_children
      enable_list = (settings[:only] + settings[:enable]).select {|e| e.start_with?(name)}

      @children = self.class.child_specs.map do |(klass, opts)|
        child = klass.new(self, **opts)
        child.enabled = false if (not self.enabled?)

        if (not settings[:only].empty?) && child.enabled?
          # Disable children unless they are explicitly enabled, or one of
          # their parents is explicitly enabled.
          child.enabled = false unless enable_list.any? {|e| child.name.start_with?(e)}
        end

        if (klass < Scope)
          # Enable Scopes if they are explicitly enabled, or one of their
          # children is explicitly enabled.
          child.enabled = enable_list.any? {|e| e.start_with?(child.name)}
        elsif (klass < Check)
          # Enable Checks if they are explicitly enabled.
          child.enabled = true if enable_list.include?(child.name)
        end

        # Disable anything explicitly listed.
        child.enabled = false if settings[:disable].include?(child.name)

        child
      end
    end
  end

  # Runtime logic for executing diagnostics
  #
  # This class implements the runtime logic of the support script which
  # consists of:
  #
  #   - Setting up runtime state, such as the output directory.
  #   - Initializng and then executing a list of {Scope} objects.
  #   - Generating output archives and disposing of any runtime state.
  class Runner
    include Configable

    def initialize(**options)
      initialize_configable

      @child_specs = []
    end

    # Add a child to be executed by this Runner instance
    #
    # @param klass [Class] the class from which the child should be
    #   initialized. Must implement a `run` method.
    # @param options [Hash] a hash of options to pass when initializing
    #   the child.
    # @return [void]
    def add_child(klass, **options)
      @child_specs.push([klass, options])
    end

    # Initialize runtime state
    #
    # This method loads required libraries, validates the runtime environment
    # and initializes output directories.
    #
    # @return [true] if setup completes successfully.
    # @return [false] if setup encounters an error.
    def setup
      ['puppet', 'facter'].each do |lib|
        begin
          require lib
        rescue ScriptError, StandardError => e
          log.error("%{exception_class} raised when loading %{library}: %{message}\n\t%{backtrace}" %
                    {exception_class: e.class,
                     library: lib,
                     message: e.message,
                     backtrace: e.backtrace.join("\n\t")})
          return false
        end
      end

      # FIXME: Replace with Scopes that are confined to Linux.
      unless /linux/i.match(Facter.value('kernel'))
        log.error('The support script is limited to Linux operating systems.')
        return false
      end

      # FIXME: Replace with Scopes that are confined to requiring root.
      unless Facter.value('identity')['privileged']
        log.error('The support script must be run with root privilages.')
        return false
      end

      true
    end

    # Execute diagnostics
    #
    # This manages the setup of output directories and other state, followed
    # by the execution of all diagnostic classes created via {add_child}, and
    # finally creates archive formats and tears down runtime state.
    #
    # @return [0] if all operations were successful.
    # @return [1] if any operation failed.
    def run
      setup or return 1

      begin
        @child_specs.each do |(klass, opts)|
          opts ||= {}
          child = klass.new(**opts)

          child.run
        end
      rescue => e
        log.error("%{exception_class} raised when executing diagnostics: %{message}\n\t%{backtrace}" %
                  {exception_class: e.class,
                   message: e.message,
                   backtrace: e.backtrace.join("\n\t")})

        return 1
      end


      return 0
    end
  end
end
end
end


module PuppetX
  module Puppetlabs
    # Collects diagnostic information about Puppet Enterprise for Support.
    class Support
      include SupportScript::Configable

      def initialize(**options)
        @doc_url = 'https://puppet.com/docs/pe/2018.1/getting_support_for_pe.html#the-pe-support-script'

        @paths = {
          puppetlabs_bin: '/opt/puppetlabs/bin',
          puppet_bin:     '/opt/puppetlabs/puppet/bin',
          server_bin:     '/opt/puppetlabs/server/bin',
          server_data:    '/opt/puppetlabs/server/data'
        }

        initialize_configable

        @pgp_recipient = 'FD172197'

        @sftp_host = 'customer-support.puppetlabs.net'
        @sftp_user = 'puppet.enterprise.support'

        # Cache lookups about this host.
        @platform = {}

        # Cache package lookups.
        @packages = {}

        # Cache user lookups.
        @users = {}

        # Count the number of appends to each drop file: used to output progress.
        @saves = {}
      end

      def run
        validate_output_directory
        validate_output_directory_disk_space
        validate_upload_key

        query_platform

        @drop_directory = create_drop_directory
        @log_file = "#{@drop_directory}/log.txt"

        create_metadata_file

        collect_scope_enterprise if settings[:scope]['enterprise']
        collect_scope_etc        if settings[:scope]['etc']
        collect_scope_log        if settings[:scope]['log']
        collect_scope_networking if settings[:scope]['networking']
        collect_scope_resources  if settings[:scope]['resources']
        collect_scope_system     if settings[:scope]['system']

        @output_archive = create_drop_directory_archive

        optionally_upload_to_puppet_support

        report_summary
      end

      #=========================================================================
      # Puppet Enterprise Services and Paths
      #=========================================================================

      # Puppet Enterprise Services

      def puppet_enterprise_services_list
        [
          'pe-ace-server',
          'pe-activemq',
          'pe-bolt-server',
          'pe-console-services',
          'pe-nginx',
          'pe-orchestration-services',
          'pe-puppetdb',
          'pe-puppetserver',
          'pe-razor-server',
          'puppet',
          'pxp-agent'
        ]
      end

      # Puppet Enterprise Directories

      def puppet_enterprise_directories_list
        [
          '/etc/puppetlabs',
          '/opt/puppetlabs',
          '/var/lib/peadmin',
          '/var/log/puppetlabs'
        ]
      end

      # Puppet Enterprise Configuration Files and Directories

      def puppet_enterprise_config_list
        files = [
          'ace-server/conf.d',
          'activemq/activemq.xml',
          'activemq/jetty.xml',
          'activemq/log4j.properties',
          'bolt-server/conf.d',
          'client-tools/orchestrator.conf',
          'client-tools/puppet-access.conf',
          'client-tools/puppet-code.conf',
          'client-tools/puppetdb.conf',
          'client-tools/services.conf',
          'code/hiera.yaml',
          'console-services/bootstrap.cfg',
          'console-services/conf.d',
          'console-services/logback.xml',
          'console-services/rbac-certificate-whitelist',
          'console-services/request-logging.xml',
          'enterprise/conf.d',
          'enterprise/hiera.yaml',
          'facter/facter.conf',
          'installer/answers.install',
          'mcollective/server.cfg',
          'nginx/conf.d',
          'nginx/nginx.conf',
          'orchestration-services/bootstrap.cfg',
          # NOTE: The PE Orchestrator stores encryption keys in its conf.d.
          #       Therefore, we explicitly list what to gather.
          'orchestration-services/conf.d/global.conf',
          'orchestration-services/conf.d/metrics.conf',
          'orchestration-services/conf.d/orchestrator.conf',
          'orchestration-services/conf.d/web-routes.conf',
          'orchestration-services/conf.d/webserver.conf',
          'orchestration-services/conf.d/inventory.conf',
          'orchestration-services/conf.d/auth.conf',
          'orchestration-services/conf.d/pcp-broker.conf',
          'orchestration-services/conf.d/analytics.conf',
          'orchestration-services/logback.xml',
          'orchestration-services/request-logging.xml',
          'puppet/auth.conf',
          'puppet/autosign.conf',
          'puppet/classfier.yaml',
          'puppet/device.conf',
          'puppet/fileserver.conf',
          'puppet/hiera.yaml',
          'puppet/puppet.conf',
          'puppet/puppetdb.conf',
          'puppet/routes.yaml',
          'puppetdb/bootstrap.cfg',
          'puppetdb/certificate-whitelist',
          'puppetdb/conf.d',
          'puppetdb/logback.xml',
          'puppetdb/request-logging.xml',
          'puppetserver/bootstrap.cfg',
          'puppetserver/code-manager-request-logging.xml',
          'puppetserver/conf.d',
          'puppetserver/logback.xml',
          'puppetserver/request-logging.xml',
          'pxp-agent/modules',
          'pxp-agent/pxp-agent.conf',
          'r10k/r10k.yaml'
        ]
        files.map { |file| "/etc/puppetlabs/#{file}" }
      end

      # Puppet Enterprise Configuration Files to Redact

      def puppet_enterprise_config_list_to_redact
        files = [
          'activemq/activemq.xml',
          'peadmin_mcollective_client.cfg',
          'mcollective/server.cfg',
          '*/conf.d/*'
        ]
        files.map { |file| "/etc/puppetlabs/#{file}" }
      end

      # System Config Files

      def system_config_list
        files = [
          'apt/apt.conf.d',
          'apt/sources.list.d',
          'dnf/dnf.conf',
          'hosts',
          'nsswitch.conf',
          'os-release',
          'resolv.conf',
          'yum.conf',
          'yum.repos.d'
        ]
        files.map { |file| "/etc/#{file}" }
      end

      # Puppet Enterprise PostgreSQL Config Files
      # Instance Variables: @paths

      def puppet_enterprise_database_config_list
        files = [
          'postgresql.conf',
          'postmaster.opts',
          'pg_ident.conf',
          'pg_hba.conf'
        ]
        files.map { |file| "#{@paths[:server_data]}/postgresql/9.6/data/#{file}" }
      end

      # Puppet Enterprise PostgreSQL Upgrade Log Files
      # Instance Variables: @paths

      def puppet_enterprise_database_upgrade_log_list
        files = [
          'pg_upgrade_internal.log',
          'pg_upgrade_server.log',
          'pg_upgrade_utility.log'
        ]
        files.map { |file| "#{@paths[:server_data]}/postgresql/#{file}" }
      end

      # Used by validate_output_directory_disk_space.

      def puppet_enterprise_directories_to_size_by_age
        [
          '/var/log/puppetlabs',
          '/opt/puppetlabs/pe_metric_curl_cron_jobs',
          '/opt/puppetlabs/puppet-metrics-collector'
        ]
      end

      # Used by validate_output_directory_disk_space.

      def puppet_enterprise_directories_to_size_for_filesync
        [
          '/etc/puppetlabs/code-staging',
          '/opt/puppetlabs/server/data/puppetserver/filesync'
        ]
      end

      #=========================================================================
      # Scopes
      #=========================================================================

      # Collect Puppet Enterprise diagnostics.
      # Instance Variables: @drop_directory, @paths, @platform

      def collect_scope_enterprise
        display 'Collecting Enterprise Diagnostics'
        display

        scope_directory = "#{@drop_directory}/enterprise"

        # Collect Puppet Enterprise packages.
        pe_packages = query_packages_matching('^pe-|^puppet')
        data_drop(pe_packages, scope_directory, 'puppet_packages.txt')

        # Collect list of Puppet Enterprise files.
        # Equivalent to list_pe_and_module_files() in puppet-enterprise-support.sh
        pe_directories = puppet_enterprise_directories_list
        pe_directories += conf_puppet_master_basemodulepath.split(':')
        pe_directories += conf_puppet_master_environmentpath.split(':')
        pe_directories += conf_puppet_master_modulepath.split(':')
        pe_directories.uniq.sort.each do |directory|
          directory_file_name = directory.tr('/', '_')
          exec_drop("ls -alR #{directory}", scope_directory, "list_#{directory_file_name}.txt".squeeze('_'))
        end

        # Collect Puppet certs.
        if SemanticPuppet::Version.parse(Puppet.version) >= SemanticPuppet::Version.parse('6.0.0')
          exec_drop("#{@paths[:puppetlabs_bin]}/puppetserver ca list --all", scope_directory, 'puppetserver_cert_list.txt')
        else
          exec_drop("#{@paths[:puppet_bin]}/puppet cert list --all", scope_directory, 'puppet_cert_list.txt')
        end

        # Collect Puppet config.
        exec_drop("#{@paths[:puppet_bin]}/puppet config print --color=false",         scope_directory, 'puppet_config_print.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet config print --color=false --debug", scope_directory, 'puppet_config_print_debug.txt')

        # Collect Puppet facts.
        exec_drop("#{@paths[:puppet_bin]}/puppet facts --color=false",         scope_directory, 'puppet_facts.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet facts --color=false --debug", scope_directory, 'puppet_facts_debug.txt')

        # Collect Puppet and Puppet Server gems.
        exec_drop("#{@paths[:puppet_bin]}/gem list --local",                  scope_directory, 'puppet_gem_list.txt')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppetserver gem list --local", scope_directory, 'puppetserver_gem_list.txt')

        # Collect Puppet modules.
        exec_drop("#{@paths[:puppet_bin]}/puppet module list --color=false",    scope_directory, 'puppet_modules_list.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet module list --render-as yaml", scope_directory, 'puppet_modules_list.yaml')

        # Collect Puppet Enterprise Environment diagnostics.
        puppetserver_environments_json = curl_puppetserver_environments
        data_drop(puppetserver_environments_json, scope_directory, 'puppetserver_environments.json')

        # Collect data using environments from the puppet/v3/environments endpoint.
        # Equivalent to puppetserver_environments() in puppet-enterprise-support.sh
        begin
          puppetserver_environments = JSON.parse(puppetserver_environments_json)
        rescue JSON::ParserError
          puppetserver_environments = {}
          logline 'error: collect_scope_enterprise: unable to parse puppetserver_environments_json'
        end
        puppetserver_environments['environments'].keys.each do |environment|
          environment_manifests = puppetserver_environments['environments'][environment]['settings']['manifest']
          environment_directory = File.dirname(environment_manifests)
          environment_modules_drop_directory = "#{scope_directory}/environments/#{environment}/modules"
          exec_drop("#{@paths[:puppet_bin]}/puppet module list --color=false --environment=#{environment}",    environment_modules_drop_directory, 'puppet_modules_list.txt')
          exec_drop("#{@paths[:puppet_bin]}/puppet module list --render-as yaml --environment=#{environment}", environment_modules_drop_directory, 'puppet_modules_list.yaml')
          # Scope Redirect: This drops into etc instead of enterprise.
          copy_drop("#{environment_directory}/environment.conf", @drop_directory)
          copy_drop("#{environment_directory}/hiera.yaml",       @drop_directory)
        end unless puppetserver_environments.empty?

        # Collect Puppet Enterprise Classifier groups.
        if settings[:classifier]
          data_drop(curl_classifier_groups, scope_directory, 'classifier_groups.json')
        end

        # Collect Puppet Enterprise Service diagnostics.
        data_drop(curl_console_status,          scope_directory, 'console_status.json')
        data_drop(curl_orchestrator_status,     scope_directory, 'orchestrator_status.json')
        data_drop(curl_puppetdb_nodes,          scope_directory, 'puppetdb_nodes.json')
        data_drop(curl_puppetdb_status,         scope_directory, 'puppetdb_status.json')
        data_drop(curl_puppetdb_summary_stats,  scope_directory, 'puppetdb_summary_stats.json')
        data_drop(curl_puppetserver_modules,    scope_directory, 'puppetserver_modules.json')
        data_drop(curl_puppetserver_status,     scope_directory, 'puppetserver_status.json')
        data_drop(curl_rbac_directory_settings, scope_directory, 'rbac_directory_settings.json')

        # Collect Puppet Enterprise Database diagnostics.
        data_drop(psql_settings,                scope_directory, 'postgres_settings.txt')
        data_drop(psql_stat_activity,           scope_directory, 'postgres_stat_activity.txt')
        data_drop(psql_thundering_herd,         scope_directory, 'thundering_herd.txt')
        data_drop(psql_replication_slots,       scope_directory, 'postgres_replication_slots.txt')
        data_drop(psql_replication_status,      scope_directory, 'postgres_replication_status.txt')

        # Collect Puppet Enterprise Code Manager/r10k diagnostics.
        codemanager_dir = "#{@paths[:server_data]}/code-manager"
        exec_drop("du -h --max-depth=1 #{codemanager_dir}", scope_directory, 'r10k_cache_sizes_from_du.txt') if File.directory?(codemanager_dir)
        r10k_yaml = '/etc/puppetlabs/r10k/r10k.yaml'
        code_manager_yaml = "#{codemanager_dir}/r10k.yaml"
        r10k_config = File.exist?(r10k_yaml) ? r10k_yaml : nil
        r10k_config = code_manager_yaml if File.exist?(code_manager_yaml)
        if r10k_config
          exec_drop("#{@paths[:puppet_bin]}/r10k deploy display -p --detail -c #{r10k_config}", scope_directory, 'r10k_deploy_display.txt')
        end

        # Collect Puppet Enterprise Mcollective diagnostics.
        if user_exists?('peadmin')
          ping_command      = %(- peadmin --shell /bin/bash --command "#{@paths[:puppet_bin]}/mco ping")
          inventory_command = %(- peadmin --shell /bin/bash --command "#{@paths[:puppet_bin]}/mco inventory #{@platform[:fqdn]}")
          timeout = 16
          exec_drop("su #{ping_command}",      scope_directory, 'mco_ping.txt', timeout)
          exec_drop("su #{inventory_command}", scope_directory, 'mco_inventory.txt', timeout)
        end

        # Collect Puppet Enterprise FileSync diagnostics.
        code_staging_directory = '/etc/puppetlabs/code-staging'
        filesync_directory =     '/opt/puppetlabs/server/data/puppetserver/filesync'
        exec_drop("du -h --max-depth=1 #{code_staging_directory}", scope_directory, 'code_staging_sizes_from_du.txt') if File.directory?(code_staging_directory)
        exec_drop("du -h --max-depth=1 #{filesync_directory}",     scope_directory, 'filesync_sizes_from_du.txt')     if File.directory?(filesync_directory)
        if settings[:filesync]
          # Scope Redirect: This drops into etc instead of enterprise.
          copy_drop(code_staging_directory, @drop_directory)
          # Scope Redirect: This drops into opt instead of enterprise.
          copy_drop(filesync_directory, @drop_directory)
        end

        # Collect Puppet Enterprise File Bucket diagnostics.
        filebucket_directory = '/opt/puppetlabs/server/data/puppetserver/bucket'
        exec_drop("du -sh #{filebucket_directory}", scope_directory, 'filebucket_size_from_du.txt') if File.directory?(filebucket_directory)

        # Collect Puppet Enterprise Infrastructure diagnostics.
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure status --format json", scope_directory, 'puppet_infra_status.json')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure tune",                 scope_directory, 'puppet_infra_tune.txt')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure tune --current",       scope_directory, 'puppet_infra_tune_current.txt')

        # Collect Puppet Enterprise Metrics.
        recreate_parent_path = false
        copy_drop_mtime('/opt/puppetlabs/pe_metric_curl_cron_jobs', @drop_directory, settings[:log_age], recreate_parent_path)
        copy_drop_mtime('/opt/puppetlabs/puppet-metrics-collector', @drop_directory, settings[:log_age], recreate_parent_path)

        # Collect all Orchestrator logs for the number of active nodes.
        recreate_parent_path = true
        copy_drop_match('/var/log/puppetlabs/orchestration-services', @drop_directory, 'aggregate-node-count*.log*', recreate_parent_path)
      end

      # Collect system configuration files.
      # Instance Variables: @drop_directory

      def collect_scope_etc
        display 'Collecting Config Files'
        display

        scope_directory = "#{@drop_directory}/etc"

        system_config_list.each do |source|
          copy_drop(source, @drop_directory)
        end

        puppet_enterprise_config_list.each do |source|
          copy_drop(source, @drop_directory)
        end

        puppet_enterprise_database_config_list.each do |source|
          # Scope Redirect: This drops into opt instead of etc.
          copy_drop(source, @drop_directory)
        end

        puppet_enterprise_services_list.each do |service|
          copy_drop("/etc/default/#{service}",   @drop_directory)
          copy_drop("/etc/sysconfig/#{service}", @drop_directory)
        end

        exec_drop('cat /var/lib/peadmin/.mcollective', "#{scope_directory}/mcollective", 'peadmin_mcollective_client.cfg')

        # Redact passwords from config files.
        unless noop?
          puppet_enterprise_config_list_to_redact.each do |file|
            command = %(ls -1 #{@drop_directory}/#{file} 2>/dev/null | xargs --no-run-if-empty sed --in-place '/password/d')
            exec_return_status(command)
          end
        end

        sos_clean("#{@drop_directory}/etc/hosts", "#{@drop_directory}/hosts")
      end

      # Collect puppet and system logs.
      # Instance Variables: @drop_directory, @paths

      def collect_scope_log
        display 'Collecting Log Files'
        display

        scope_directory = "#{@drop_directory}/var/log"

        copy_drop('/var/log/messages',     @drop_directory)
        copy_drop('/var/log/syslog',       @drop_directory)
        copy_drop('/var/log/system',       @drop_directory)

        if documented_option?('dmesg', '--ctime')
          if documented_option?('dmesg', '--time-format')
            exec_drop('dmesg --ctime --time-format iso', scope_directory, 'dmesg.txt')
          else
            exec_drop('dmesg --ctime', scope_directory, 'dmesg.txt')
          end
        else
          exec_drop('dmesg', scope_directory, 'dmesg.txt')
        end

        copy_drop('/var/log/puppetlabs/installer', @drop_directory)

        recreate_parent_path = true
        copy_drop_mtime('/var/log/puppetlabs', @drop_directory, settings[:log_age], recreate_parent_path)

        puppet_enterprise_services_list.each do |service|
          exec_drop("journalctl --full --output=short-iso --unit=#{service} --since '#{settings[:log_age]} days ago'", scope_directory, "#{service}-journalctl.log")
        end

        exec_drop('cat /var/lib/peadmin/.mcollective.d/client.log', scope_directory, 'peadmin_mcollective_client.log')

        recreate_parent_path = false
        puppet_enterprise_database_upgrade_log_list.each do |source|
          copy_drop(source, scope_directory, recreate_parent_path)
        end
      end

      # Collect system networking diagnostics.
      # Instance Variables: @platform

      def collect_scope_networking
        display 'Collecting Networking Diagnostics'
        display

        scope_directory = "#{@drop_directory}/networking"

        data_drop(@platform[:hostname], scope_directory, 'hostname.txt')
        exec_drop('ifconfig -a',        scope_directory, 'ifconfig.txt')
        exec_drop('iptables -L',        scope_directory, 'iptables.txt')
        exec_drop('ip6tables -L',       scope_directory, 'iptables.txt')
        exec_drop('netstat -anptu',     scope_directory, 'ports.txt')
        exec_drop('ntpq -p',            scope_directory, 'ntpq.txt')

        unless executable?('iptables')
          exec_drop('lsmod | grep ip', scope_directory, 'ip_modules.txt')
        end

        # Puppet Networking:

        unless noop?
          command = %(ping -t1 -c1 #{@platform[:hostname]})
          ip_address = exec_return_result(command).split(' ')[2].tr('()', '')
          data_drop(ip_address, scope_directory, 'ip_address.txt')
          if ip_address
            command = %(getent hosts #{ip_address})
            mapped_hostname = exec_return_result(command)
            data_drop(mapped_hostname, scope_directory, 'ip_address_hostnames.txt')
          end
          exec_drop("ping -c 1 #{conf_puppet_agent_server}", scope_directory, 'puppet_ping.txt')
        end

        sos_clean("#{scope_directory}/hostname.txt", "#{@drop_directory}/hostname")
      end

      # Collect system resource usage diagnostics.
      # Instance Variables: @drop_directory, @paths

      def collect_scope_resources
        display 'Collecting Resources Diagnostics'
        display

        scope_directory = "#{@drop_directory}/resources"

        exec_drop('df -h',   scope_directory, 'df_h_output.txt')
        exec_drop('df -i',   scope_directory, 'df_i_output.txt')
        exec_drop('df -k',   scope_directory, 'df_k_output.txt')
        exec_drop('free -h', scope_directory, 'free_h.txt')

        # Puppet Resources:

        exec_drop("ls -1 -d #{@paths[:server_data]}/postgresql/*/data  | xargs du -sh", scope_directory, 'db_sizes_from_du.txt')
        exec_drop("ls -1 -d #{@paths[:server_data]}/postgresql/*/PG_9* | xargs du -sh", scope_directory, 'db_table_sizes_from_du.txt')

        psql_data = psql_database_sizes
        data_drop(psql_data, scope_directory, 'db_sizes_from_psql.txt')

        databases = psql_databases
        databases = databases.lines.map(&:strip).grep(%r{^pe\-}).sort
        databases.each do |database|
          database_size_from_psql = psql_database_relation_sizes(database)
          data_drop(database_size_from_psql, scope_directory, 'db_relation_sizes_from_psql.txt')
        end
      end

      # Collect system diagnostics.
      # Instance Variables: @drop_directory, @paths

      def collect_scope_system
        display 'Collecting System Diagnostics'
        display

        scope_directory = "#{@drop_directory}/system"

        exec_drop('env',                  scope_directory, 'env.txt')
        exec_drop('lsb_release -a',       scope_directory, 'lsb_release.txt')
        exec_drop('ps -aux',              scope_directory, 'ps_aux.txt')
        exec_drop('ps -ef',               scope_directory, 'ps_ef.txt')
        exec_drop('sestatus',             scope_directory, 'selinux.txt')
        exec_drop('chkconfig --list',     scope_directory, 'services.txt')
        exec_drop('svcs -a',              scope_directory, 'services.txt')
        exec_drop('systemctl list-units', scope_directory, 'services.txt')
        exec_drop('umask',                scope_directory, 'umask.txt')
        exec_drop('uname -a',             scope_directory, 'uname.txt')
        exec_drop('uptime',               scope_directory, 'uptime.txt')

        puppet_enterprise_services_list.each do |service|
          ['memory','cpu','blkio','devices','pids','systemd'].each do |fs|
            copy_drop_match("/sys/fs/cgroup/#{fs}/system.slice/#{service}.service/", scope_directory, '*')
          end
        end
        FileUtils.chmod_R('u+wX', "#{scope_directory}/sys") if File.exist?("#{scope_directory}/sys")

        pids = Array.new
        pids.push(exec_return_result('pgrep -f "puppetlabs/ace-server"'))
        pids.push(exec_return_result('pgrep -f "puppetlabs/bolt-server"'))
        if(File.exists?('/var/run/puppetlabs/agent.pid'))
          pids.push(File.read('/var/run/puppetlabs/agent.pid'))
        end
        pids.push(exec_return_result('pidof pxp-agent'))

        ['console-services','orchestration-services','puppetdb','puppetserver'].each do |service|
          pidfile = "/var/run/puppetlabs/#{service}/#{service}.pid"
          if File.readable?(pidfile)
            pids.push(File.read(pidfile).chomp!)
          end
        end
        pids.each do |pid|
          next unless ( pid.match?(/^\d+$/) && Dir.exists?("/proc/#{pid}") )
          destpath="#{scope_directory}/proc/#{pid}"
          ['cmdline','limits','environ'].each do |procfile|
            copy_drop("/proc/#{pid}/#{procfile}", scope_directory)
          end
          data_drop(File.readlink("/proc/#{pid}/exe"), destpath, 'exe')
        end
        FileUtils.chmod_R('u+wX', "#{scope_directory}/proc") unless pids.empty?

        puppet_enterprise_services_list.each do |service|
          exec_drop("systemctl status #{service}", scope_directory, 'systemctl-status.txt')
          data_drop("=" * 100 + "\n", scope_directory, 'systemctl-status.txt')
        end
      end

      #=========================================================================
      # Output
      #=========================================================================

      # Execute a command and append the results to a file in the destination directory.
      #
      # Rather than testing for the existance of a related feature the calling scope,
      # test for the existance of the command in the method.

      def exec_drop(command_line, dst, file, timeout = 0)
        command = command_line.split(' ')[0]
        unless command
          logline "exec_drop: command not found in: #{command_line}"
          return false
        end
        file_name = "#{dst}/#{file}"
        command_line = %(#{command_line} 2>&1 >> "#{file_name}")
        unless executable?(command)
          logline "exec_drop: command not found: #{command} cannot execute: #{command_line}"
          return false
        end
        logline "exec_drop: #{command_line}"
        if @saves.key?(file_name)
          @saves[file_name] = @saves[file_name] + 1
          display " ** Append: #{file} # #{@saves[file_name]}"
        else
          display " ** Saving: #{file}"
          @saves[file_name] = 1
        end
        display
        return if noop?
        return false unless create_path(dst)
        exec_return_status(command_line, timeout)
      end

      # Append data to a file in the destination directory.

      def data_drop(data, dst, dst_file)
        dst_file_path = "#{dst}/#{dst_file}"
        logline "data_drop: to #{dst_file_path}"
        if @saves.key?(dst_file_path)
          @saves[dst_file_path] = @saves[dst_file_path] + 1
          display " ** Append: #{dst_file} # #{@saves[dst_file_path]}"
        else
          display " ** Saving: #{dst_file}"
          @saves[dst_file_path] = 1
        end
        display
        return if noop?
        return false unless create_path(dst)
        # data = 'This file is empty.' if data == ''
        File.open(dst_file_path, 'a') { |file| file.puts(data) }
      end

      # Copy directories or files to the destination directory, recreating the parent path by default.
      #
      # Rather than testing for the existance of the source in the calling scope,
      # test for the existance of the source in the method.

      def copy_drop(src, dst, recreate_parent_path = true)
        parents_option = recreate_parent_path ? ' --parents' : ''
        recursive_option = File.directory?(src) ? ' --recursive' : ''
        command_line = %(cp --dereference --preserve #{parents_option} #{recursive_option} "#{src}" "#{dst}")
        unless File.exist?(src)
          logline "copy_drop: source not found: #{src}"
          return false
        end
        logline "copy_drop: #{command_line}"
        display " ** Saving: #{src}"
        display
        return if noop?
        return false unless create_path(dst)
        exec_return_status(command_line)
      end

      # Copy files newer than age to the destination directory, recreating the parent path by default.

      def copy_drop_mtime(src, dst, age, recreate_parent_path = true)
        parents_option = recreate_parent_path ? ' --parents' : ''
        command_line = %(find #{src} -type f -mtime -#{age} | xargs --no-run-if-empty cp --preserve #{parents_option} --target-directory #{dst})
        unless File.exist?(src)
          logline "copy_drop_mtime: source not found: #{src}"
          return false
        end
        logline "copy_drop_mtime: #{command_line}"
        display " ** Saving: #{src} files newer than #{age} days"
        display
        return if noop?
        return false unless create_path(dst)
        exec_return_status(command_line)
      end

      # Copy files with names matching a glob to the destination directory, recreating the parent path by default.

      def copy_drop_match(src, dst, glob, recreate_parent_path = true)
        parents_option = recreate_parent_path ? ' --parents' : ''
        command_line = %(find #{src} -type f -name "#{glob}" | xargs --no-run-if-empty cp --preserve #{parents_option} --target-directory #{dst})
        unless File.exist?(src)
          logline "copy_drop_match: source not found: #{src}"
          return false
        end
        logline "copy_drop_match: #{command_line}"
        display " ** Saving: #{src} files with a name matching '#{glob}'"
        display
        return if noop?
        return false unless create_path(dst)
        exec_return_status(command_line)
      end

      # Create a path.

      def create_path(path)
        exec_return_status(%(mkdir --parents "#{path}"))
      end

      # Create a symlink to allow SOScleaner to redact hostnames in the output.
      # https://github.com/RedHatGov/soscleaner

      def sos_clean(file, link)
        command = %(ln --relative --symbolic "#{file}" "#{link}")
        logline "sos_clean: #{command}"
        return if noop?
        exec_return_status(command)
      end

      #=========================================================================
      # Inspection
      #=========================================================================

      # Validate the output directory, or exit.
      def validate_output_directory
        fail_and_exit("Output directory #{settings[:dir]} does not exist") unless File.directory?(settings[:dir])
        fail_and_exit("Output directory #{settings[:dir]} cannot be a symlink") if File.symlink?(settings[:dir])
      end

      # Verify free disk space for the output directory, or exit.
      def validate_output_directory_disk_space
        available = 0
        required = 32_768
        puppet_enterprise_directories_to_size_by_age.each do |directory|
          if File.directory?(directory)
            used = exec_return_result(%(find #{directory} -type f -mtime -#{settings[:log_age]} -exec du -sk {} \\; | cut -f1 | awk '{total=total+$1}END{print total}').chomp)
            required += used.to_i unless used == ''
          end
        end
        if settings[:filesync]
          puppet_enterprise_directories_to_size_for_filesync.each do |directory|
            if File.directory?(directory)
              used = exec_return_result(%(du -sk #{directory} | cut -f1).chomp)
              required += used.to_i unless used == ''
            end
          end
        end
        # Double the total used by source directories, to account for the original output directory and compressed archive.
        required = (required * 2) / 1024
        free = exec_return_result(%(df -Pk "#{settings[:dir]}" | grep -v Available).chomp)
        available = free.split(' ')[3].to_i / 1024 unless free == ''
        fail_and_exit("Not enough free disk space in #{settings[:dir]}. Available: #{available} MB, Required: #{required} MB") if available < required
      end

      # Verify upload key exists if specified, or exit.

      def validate_upload_key
        return unless settings[:upload_key]
        fail_and_exit("#{settings[:upload_key]} does not exist") unless File.exists?(settings[:upload_key])
      end

      # Query the runtime platform.
      # Instance Variables: @platform
      #
      # name      : Name of the platorm, e.g. "centos".
      # release   : Release version, e.g. "10.10".
      # hostname  : Hostname of this machine, e.g. "host".
      # fqdn      : Fully qualified hostname of this machine, e.g. "host.example.com".
      # packaging : Name of packaging system, e.g. "rpm".

      def query_platform
        os = Facter.value('os')
        @platform[:name]     = os['name'].downcase
        @platform[:release]  = os['release']['full']
        @platform[:hostname] = Facter.value('hostname').downcase
        @platform[:fqdn]     = Facter.value('fqdn').downcase
        case @platform[:name]
        when 'amazon', 'aix', 'centos', 'eos', 'fedora', 'redhat', 'rhel', 'sles'
          @platform[:packaging] = 'rpm'
        when 'debian', 'cumulus', 'ubuntu'
          @platform[:packaging] = 'dpkg'
        else
          @platform[:packaging] = ''
          display_warning("Unknown packaging system for platform: #{@platform[:name]}")
        end
      end

      # Query packages that are part of the Puppet Enterprise installation
      # Instance Variables: @platform

      def query_packages_matching(regex)
        result = ''
        acsiibar = '=' * 80
        case @platform[:packaging]
        when 'rpm'
          packages = exec_return_result(%(rpm --query --all | grep --extended-regexp '#{regex}'))
          result = packages
          packages.lines do |package|
            result << "\nPackage: #{package}\n"
            result << exec_return_result(%(rpm --verify #{package}))
            result << "\n#{acsiibar}\n"
          end
        when 'dpkg'
          packages = exec_return_result(%(dpkg-query --show --showformat '${Package}\n' | grep --extended-regexp '#{regex}'))
          result = packages
          packages.lines do |package|
            result << "\nPackage: #{package}\n"
            result << exec_return_result(%(dpkg --verify #{package}))
            result << "\n#{acsiibar}\n"
          end
        else
          logline "query_packages_matching: unable to list packages for platform: #{@platform[:name]}"
          display_warning("Unable to list packages for platform: #{@platform[:name]}")
        end
        result
      end

      # Query a package and cache the results.
      # Instance Variables: @platform, @packages

      def package_installed?(package)
        status = false
        return @packages[package] if @packages.key?(package)
        case @platform[:packaging]
        when 'rpm'
          status = exec_return_result(%(rpm --query --info #{package})) =~ %r{Version}
        when 'dpkg'
          status = exec_return_status(%(dpkg-query  --show #{package}))
        else
          logline "package_installed: unable to query package for platform: #{@platform[:name]}"
          display_warning("Unable to query package for platform: #{@platform[:name]}")
        end
        @packages[package] = status
      end

      # Query a user and cache the results.
      # Instance Variables: @users

      def user_exists?(username)
        return false unless username
        return @users[username] if @users.key?(username)
        command = %(getent passwd #{username})
        result = exec_return_status(command)
        @users[username] = result
      end

      #=========================================================================
      # Puppet Configuration Settings
      #=========================================================================

      def conf_puppet_agent_server
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent server))
        setting = 'puppet' if setting == ''
        setting
      end

      def conf_puppet_agent_hostcert
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent hostcert))
        setting = exec_return_result(%(/etc/puppetlabs/puppet/ssl/certs/$(hostname -f).pem)) if setting == ''
        setting
      end

      def conf_puppet_agent_hostprivkey
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent hostprivkey))
        setting = exec_return_result(%(/etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f).pem)) if setting == ''
        setting
      end

      def conf_puppet_master_basemodulepath
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master basemodulepath))
        setting = '/etc/puppetlabs/code/modules:/opt/puppetlabs/puppet/modules' if setting == ''
        setting
      end

      def conf_puppet_master_environmentpath
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master environmentpath))
        setting = '/etc/puppetlabs/code/environments' if setting == ''
        setting
      end

      def conf_puppet_master_modulepath
        setting = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master modulepath))
        setting = '/etc/puppetlabs/code/environments/production/modules:/etc/puppetlabs/code/modules:/opt/puppetlabs/puppet/modules' if setting == ''
        setting
      end

      #=========================================================================
      # Query Puppet Enterprise API
      #=========================================================================

      # Common curl parameters used by the curl_* methods.

      def curl_auth
        "--cert #{conf_puppet_agent_hostcert} --key #{conf_puppet_agent_hostprivkey}"
      end

      def curl_opts
        '--silent --show-error --connect-timeout 5 --max-time 60'
      end

      # Port 8080 is often used by other services.

      def puppetdb_port
        setting = exec_return_result(%(cat /etc/puppetlabs/puppetdb/conf.d/jetty.ini | sed 's/ //g' | grep --extended-regexp '^port=[[:digit:]]+$'))
        (setting == '') ? 8080 : setting.split('=')[1]
      end

      def puppetdb_ssl_port
        setting = exec_return_result(%(cat /etc/puppetlabs/puppetdb/conf.d/jetty.ini | sed 's/ //g' | grep --extended-regexp '^ssl-port=[[:digit:]]+$'))
        (setting == '') ? 8081 : setting.split('=')[1]
      end

      # Execute a curl command and return the results or an empty string.
      # Instance Variables: @paths

      def curl_console_status
        return '' unless package_installed?('pe-console-services')
        status = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} -X GET http://127.0.0.1:4432/status/v1/services?level=debug))
        pretty_json(status)
      end

      def curl_orchestrator_status
        return '' unless package_installed?('pe-orchestration-services')
        status = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} --insecure -X GET https://127.0.0.1:8143/status/v1/services?level=debug))
        pretty_json(status)
      end

      def curl_puppetserver_status
        return '' unless package_installed?('pe-puppetserver')
        status = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} --insecure -X GET https://127.0.0.1:8140/status/v1/services?level=debug))
        pretty_json(status)
      end

      def curl_puppetdb_status
        return '' unless package_installed?('pe-puppetdb')
        status = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:#{puppetdb_ssl_port}/status/v1/services?level=debug))
        pretty_json(status)
      end

      def curl_classifier_groups
        return '' unless package_installed?('pe-console-services')
        groups = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:4433/classifier-api/v1/groups))
        pretty_json(groups)
      end

      def curl_puppetdb_nodes
        return '' unless package_installed?('pe-puppetdb')
        query = 'query=nodes[certname] {deactivated is null and expired is null}'
        nodes = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:#{puppetdb_ssl_port}/pdb/query/v4 --data-urlencode '#{query}'))
        pretty_json(nodes)
      end

      def curl_puppetdb_summary_stats
        return '' unless package_installed?('pe-puppetdb')
        status = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:#{puppetdb_ssl_port}/pdb/admin/v1/summary-stats))
        pretty_json(status)
      end

      def curl_puppetserver_environments
        return '' unless package_installed?('pe-puppetserver')
        environments = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:8140/puppet/v3/environments))
        pretty_json(environments)
      end

      def curl_puppetserver_modules
        return '' unless package_installed?('pe-puppetserver')
        modules = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:8140/puppet/v3/environment_modules))
        pretty_json(modules)
      end

      def curl_rbac_directory_settings
        return '' unless package_installed?('pe-console-services')
        settings = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure -X GET https://127.0.0.1:4433/rbac-api/v1/ds))
        blacklist = %w[password ds_pw_obfuscated]
        pretty_json(settings, blacklist)
      end

      #=========================================================================
      # Query Puppet PostgreSQL
      #=========================================================================

      # Execute a psql command using the pe-postgres and return the results or an empty string.
      # Instance Variables: @paths

      def psql_databases
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT datname FROM pg_catalog.pg_database;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --tuples-only --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_database_sizes
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT t1.datname AS db_name, pg_size_pretty(pg_database_size(t1.datname)) FROM pg_database t1 ORDER BY pg_database_size(t1.datname) DESC;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_database_relation_sizes(database)
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        result = "#{database}\n\n"
        sql = "SELECT '#{database}' AS db_name, nspname || '.' || relname AS relation, pg_size_pretty(pg_relation_size(C.oid)) \
          FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace) WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') \
          ORDER BY pg_relation_size(C.oid) DESC;"
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname #{database} --command \\"#{sql}\\"")
        result << exec_return_result(command)
      end

      def psql_settings
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_settings;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --tuples-only --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_stat_activity
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_stat_activity ORDER BY query_start;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_replication_slots
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_replication_slots;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname pe-puppetdb --command \\"#{sql}\\"")
        exec_return_result(command)
      end

      def psql_replication_status
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_stat_replication;'
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname pe-puppetdb --command \\"#{sql}\\"")
        exec_return_result(command)
      end

      def psql_thundering_herd
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = "SELECT date_part('month', start_time) AS month, date_part('day', start_time) \
          AS day, date_part('hour', start_time) AS hour, date_part('minute', start_time) as minute, count(*) \
          FROM reports \
          WHERE start_time BETWEEN now() - interval '7 days' AND now() \
          GROUP BY date_part('month', start_time), date_part('day', start_time), date_part('hour', start_time), date_part('minute', start_time) \
          ORDER BY date_part('month', start_time) DESC, date_part('day', start_time) DESC, date_part( 'hour', start_time ) DESC, date_part('minute', start_time) DESC;"
        command = %(su pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname pe-puppetdb --command \\"#{sql}\\"")
        exec_return_result(command)
      end

      #=========================================================================
      # Manage Output Directory and Output Archive
      #=========================================================================

      # Create the drop directory, or exit.
      # Instance Variables: @platform

      def create_drop_directory
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        drop_directory = ["#{settings[:dir]}/puppet_enterprise_support", settings[:ticket], @platform[:hostname], timestamp].reject(&:empty?).join('_')
        if unsupported_drop_directory?(drop_directory)
          fail_and_exit("Unsupported output directory: #{drop_directory}")
        end
        display "Creating output directory: #{drop_directory}"
        display
        exec_or_fail(%(rm -rf "#{drop_directory}"))
        exec_or_fail(%(mkdir -p "#{drop_directory}"))
        exec_or_fail(%(chmod 700 "#{drop_directory}"))
        drop_directory
      end

      # Create the metadata file.
      # Instance Variables: @drop_directory

      def create_metadata_file
        begin
          metadata = JSON.pretty_generate(settings)
        rescue JSON::GeneratorError
          metadata = '{}'
          logline 'error: pretty_json: unable to generate json'
        end
        data_drop(metadata, @drop_directory, 'metadata.json')
      end

      # Avoid interacting with the following system directories.

      def unsupported_drop_directory?(directory)
        return true if directory.nil?
        return true if directory == ''
        absolute_path = File.realdirpath(directory)
        return true if ['/', '/boot', '/dev', '/proc', '/run', '/sys'].include?(absolute_path)
        false
      end

      # Archive, compress, and optionally encrypt the drop directory or exit.
      # Instance Variables: @drop_directory, @pgp_recipient

      def create_drop_directory_archive
        display "Processing output directory: #{@drop_directory}"
        display
        display " ** Archiving output directory: #{@drop_directory}"
        display
        tar_change_directory = File.dirname(@drop_directory)
        tar_directory = File.basename(@drop_directory)
        output_archive = "#{@drop_directory}.tar.gz"
        old_umask = File.umask
        begin
          File.umask(0077)
          exec_or_fail(%(tar --create --file - --directory "#{tar_change_directory}" "#{tar_directory}" | gzip --force -9 > "#{output_archive}"))
        ensure
          File.umask(old_umask)
        end
        delete_drop_directory
        if settings[:encrypt]
          gpg_command = executable?('gpg') ? 'gpg' : nil
          gpg_command = 'gpg2' if executable?('gpg2')
          unless gpg_command
            fail_and_exit('Could not find gpg or gpg2 on the PATH. GPG must be installed to use the --encrypt option')
          end
          display " ** Encrypting output archive file: #{output_archive}"
          display
          exec_or_fail(%(mkdir "#{@drop_directory}/gpg"))
          exec_or_fail(%(chmod 600 "#{@drop_directory}/gpg"))
          exec_or_fail(%(echo "#{pgp_public_key}" | "#{gpg_command}" --quiet --import --homedir "#{@drop_directory}/gpg"))
          exec_or_fail(%(#{gpg_command} --quiet --homedir "#{@drop_directory}/gpg" --trust-model always --recipient #{@pgp_recipient} --encrypt "#{output_archive}"))
          exec_or_fail(%(rm -f "#{output_archive}"))
          output_archive = "#{output_archive}.gpg"
        end
        output_archive
      end

      # Delete the drop directory or exit.
      # Instance Variables: @drop_directory

      def delete_drop_directory
        return if settings[:z_do_not_delete_drop_directory]
        if unsupported_drop_directory?(@drop_directory)
          fail_and_exit("Unsupported output directory: #{@drop_directory}")
        end
        display "Deleting output directory: #{@drop_directory}"
        display
        exec_or_fail(%(rm -rf "#{@drop_directory}"))
      end

      # Optionally upload the archive file to Puppet Support.
      # Instance Variables: @sftp_host, @sftp_user, @output_archive

      def optionally_upload_to_puppet_support
        return unless settings[:upload]
        display "Uploading: #{@output_archive} via SFTP"
        display
        unless executable?('sftp')
          display ' ** Unable to upload archive file: sftp command unavailable'
          display
          return
        end

        if settings[:upload_disable_host_key_check]
          ssh_known_hosts = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
        else
          ssh_known_hosts_file = Tempfile.new('csp.ky')
          ssh_known_hosts_file.write(sftp_ssh_known_hosts)
          ssh_known_hosts_file.close
          ssh_known_hosts = "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=#{ssh_known_hosts_file.path}"
        end
        if settings[:upload_user]
          sftp_url = "#{settings[:upload_user]}@#{@sftp_host}:/"
        else
          sftp_url = "#{@sftp_user}@#{@sftp_host}:/drop/"
        end
        if settings[:upload_key]
          ssh_key_file = File.absolute_path(settings[:upload_key])
          ssh_identity = "IdentityFile=#{ssh_key_file}"
        else
          ssh_key_file = Tempfile.new('pes.ky')
          ssh_key_file.write(default_sftp_key)
          ssh_key_file.close
          ssh_identity = "IdentityFile=#{ssh_key_file.path}"
        end
        # https://stribika.github.io/2015/01/04/secure-secure-shell.html
        # ssh_ciphers        = 'Ciphers=chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr'
        # ssh_kex_algorithms = 'KexAlgorithms=curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256'
        # ssh_macs         = 'MACs=hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com'
        ssh_ciphers        = 'Ciphers=aes256-ctr,aes192-ctr,aes128-ctr'
        ssh_kex_algorithms = 'KexAlgorithms=diffie-hellman-group-exchange-sha256'
        ssh_macs           = 'MACs=hmac-sha2-512,hmac-sha2-256'
        ssh_options        = %(-o "#{ssh_ciphers}" -o "#{ssh_kex_algorithms}" -o "#{ssh_macs}" -o "Protocol=2" -o "ConnectTimeout=16"  #{ssh_known_hosts} -o "#{ssh_identity}" -o "BatchMode=yes")
        sftp_command       = %(echo 'put #{@output_archive}' | sftp #{ssh_options} #{sftp_url} 2>&1)

        begin
          sftp_output = Facter::Core::Execution.execute(sftp_command)
          if $?.to_i.zero?
            display "File uploaded to: #{@sftp_host}"
            display
            File.delete(@output_archive)
          else
            ssh_key_file.unlink unless settings[:upload_key]
            ssh_known_hosts_file.unlink unless settings[:upload_disable_host_key_check]
            display ' ** Unable to upload the output archive file. SFTP Output:'
            display
            display sftp_output
            display
            display '    Please manualy upload the output archive file to Puppet Support.'
            display
            display "    Output archive file: #{@output_archive}"
            display
          end
        rescue Facter::Core::Execution::ExecutionFailure => e
          ssh_key_file.unlink unless settings[:upload_key]
          ssh_known_hosts_file.unlink unless settings[:upload_disable_host_key_check]
          display ' ** Unable to upload the output archive file: SFTP command error:'
          display
          display e
          display
          display '    Please manualy upload the output archive file to Puppet Support.'
          display
          display "    Output archive file: #{@output_archive}"
          display
        end
      end

      # Summary.
      # Instance Variables: @sftp_host, @doc_url, @output_archive

      def report_summary
        unless settings[:upload]
          display 'Puppet Enterprise customers ...'
          display
          display '  We recommend that you examine the collected data before forwarding to Puppet,'
          display '  as it may contain sensitive information that you may wish to redact.'
          display
          display '  An overview of the data collected by this tool can be found at:'
          display "  #{@doc_url}"
          display
          display '  Please upload the output archive file to Puppet Support.'
          display
          display "  Output archive file: #{@output_archive}"
          display
        end
        display 'Done!'
        display
      end

      #=========================================================================
      # Utilities
      #=========================================================================

      # Display a message.

      def display(info = '')
        puts info
      end

      # Display an error message.

      def display_warning(info = '')
        warn info
      end

      # Display an error message, and exit.

      def fail_and_exit(datum)
        display_warning(datum)
        exit 1
      end

      # Log to a log file.
      # Instance Variables: @log_file

      def logline(datum)
        File.open(@log_file, 'a') { |file| file.puts(datum) }
      end

      # Execute a command line and return the result or an empty string.
      # Used by methods that collect diagnostics.

      def exec_return_result(command_line, timeout = 0)
        options = { timeout: timeout }
        Facter::Core::Execution.execute(command_line, options)
      rescue Facter::Core::Execution::ExecutionFailure => e
        logline "error: exec_return_result: command failed: #{command_line} with error: #{e}"
        display "    Command failed: #{command_line} with error: #{e}"
        display
        ''
      end

      # Execute a command line and return true or false.

      def exec_return_status(command_line, timeout = 0)
        options = { timeout: timeout }
        Facter::Core::Execution.execute(command_line, options)
        $?.to_i.zero?
      rescue Facter::Core::Execution::ExecutionFailure => e
        logline "error: exec_return_status: command failed: #{command_line} with error: #{e}"
        display "    Command failed: #{command_line} with error: #{e}"
        display
        false
      end

      # Execute a command line or fail.
      # Used by methods that manage the drop directory or output archive.

      def exec_or_fail(command_line, timeout = 0)
        options = { timeout: timeout }
        Facter::Core::Execution.execute(command_line, options)
        unless $?.to_i.zero?
          raise Facter::Core::Execution::ExecutionFailure, $?
        end
      rescue Facter::Core::Execution::ExecutionFailure => e
        logline "error: exec_or_fail: command failed: #{command_line} with error: #{e}"
        fail_and_exit("Command failed: #{command_line} with error: #{e}")
      end

      # Test for command existance.

      def executable?(command)
        Facter::Core::Execution.which(command)
      end

      # Test for command option existance.

      def documented_option?(command, option)
        if help_option?(command)
          command_line = "#{command} --help | grep -q -- '#{option}' > /dev/null 2>&1"
        else
          command_line = "man #{command}    | grep -q -- '#{option}' > /dev/null 2>&1"
        end
        Facter::Core::Execution.execute(command_line)
        $?.to_i.zero?
      rescue Facter::Core::Execution::ExecutionFailure => e
        false
      end

      def help_option?(command)
        command_line = "#{command} --help > /dev/null 2>&1"
        Facter::Core::Execution.execute(command_line)
        $?.to_i.zero?
      rescue Facter::Core::Execution::ExecutionFailure => e
        false
      end

      # Test for noop mode.
      def noop?
        settings[:noop] == true
      end

      # Pretty Format JSON, minus a list of blacklisted keys.

      def pretty_json(text, blacklist = [])
        return text if text == ''
        begin
          json = JSON.parse(text)
        rescue JSON::ParserError
          logline 'error: pretty_json: unable to parse json'
          return
        end
        blacklist.each do |blacklist_key|
          if json.is_a?(Array)
            json.each do |item|
              if item.is_a?(Hash)
                item.delete(blacklist_key) if item.key?(blacklist_key)
              end
            end
          end
          if json.is_a?(Hash)
            json.delete(blacklist_key) if json.key?(blacklist_key)
          end
        end
        begin
          JSON.pretty_generate(json)
        rescue JSON::GeneratorError
          logline 'error: pretty_json: unable to generate json'
          return
        end
      end

      #=========================================================================
      # Data
      #=========================================================================

      def pgp_public_key
        result = <<-'PGPPUBLICKEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2.0.14 (GNU/Linux)

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
xfhzX6eZ+xft
=j4/z
-----END PGP PUBLIC KEY BLOCK-----
PGPPUBLICKEY
        result
      end

      def default_sftp_key
        result = <<-'SSHKEY'
-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----
SSHKEY
        result
      end

      def sftp_ssh_known_hosts
        result = <<-'SSHKNOWNHOSTS'
# Primary
customer-support.puppetlabs.net ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCrLB9mWc9pxVjUin3LtIRj3vMmqgv8oUKa/JAfXkRVoKgF7EYmmsjCU55pg+ZFBUD87hJ9JNKVM8TGEQ89sjnPBN6lCdKn0sc4wfVHqbh70VvX7LhQPM79eUUkvdfHcRep1VsgWrxJlKZH42X+ermWrnzE+1vz2OB/edDOjG4Ku/gh7YHFTS1VyPzf+R0q5Nl0VQvo0RHXaeVVNMLlMy5BuRQCU1+WPKKHtH+ZvzfE6/rc/CR8L4PKzcHuQN5n1bcl13hlsYr+IHMkESJyZWIHeZiKUSa7hu464Nl0LNGhDLN25bAZrqiFwiyNEhz1+v1BOhhgkFJ0vWSoKPlsqS55
customer-support.puppetlabs.net ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOwBtY6ojejMa6tl9QSAWDi2pSpTYBKldD3r6kIOJDTd2b7x99WQPFhJgWdJ76ANIolvEWI5lAkvFwMJ5SMG5Ak=
customer-support.puppetlabs.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO8GiFNutya82Ya+xeI8LWEbA2EmwVQF5gtvjsJ6s+W0
# Asia-Pacific
customer-support-syd.puppetlabs.net ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw9P+9D/QFSveyYQUEIkB0Ii9OPZpna32x05RKgMslFZWXyctXfhoFQvtE/df9TfcYA8dFZuibJZamQKwQ6VPjkbk7YdMpWbho5X9j78B7Dr74iQQKzZzLUYf4Nqrjpo+S6lHGLTA2Oxt8Hi6a7FqYqzVDR8umuetncLsPMSpjlU+veAcMIhPa5Lvw7m8dOoeiBfLs3TL+HgLMr/IUJ31QLUDIRDnB6nVBwoUU3OW+an9JksIeGyoB0kqT86nW22jFaZpzJ5YeRWvtmrlZkPjpjayPb91rKLd8ZLQGTR3Y55yArok9Q55+C74LsouNyFMKKdoa4dOh7ikhJ5wE1dU1
customer-support-syd.puppetlabs.net ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFUTiJ8+OWy3QIF2ajlOaiE7k10Ae1TP9eh4ClgNMKvrGXojaJ/qztQHGQbhsDLQT0BduJ24ow58bXebziz5JCs=
customer-support-syd.puppetlabs.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+v91GesXhPY9+hpOTqPIFlyFkMT8CrKDVNL7vFycP2
SSHKNOWNHOSTS
        result
      end
    end
  end
end


# The following allows this class to be executed as a standalone script.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'optparse'

  # See also: lib/puppet/face/enterprise/support.rb
  default_dir     = File.directory?('/var/tmp') ? '/var/tmp' : '/tmp'
  default_log_age = 14
  default_scope   = %w[enterprise etc log networking resources system].join(',')

  puts 'Puppet Enterprise Support Script'
  puts

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
    opts.separator ''
    opts.separator 'Summary: Collects Puppet Enterprise Support Diagnostics'
    opts.separator ''
    opts.separator 'Options:'
    opts.separator ''
    opts.on('-c', '--classifier', 'Include Classifier data') do
      options[:classifier] = true
    end
    opts.on('-d', '--dir DIRECTORY', "Output directory. Defaults to: #{default_dir}") do |dir|
      options[:dir] = dir
    end
    opts.on('-e', '--encrypt', 'Encrypt output using GPG') do
      options[:encrypt] = true
    end
    opts.on('-f', '--filesync', 'Include FileSync data') do
      options[:filesync] = true
    end
    opts.on('-l', '--log_age DAYS', "Log age (in days) to collect. Defaults to: #{default_log_age}") do |log_age|
      options[:log_age] = log_age
    end
    opts.on('-n', '--noop', 'Enable noop mode') do
      options[:noop] = true
    end
    opts.on('-s', '--scope LIST', "Scope (comma-delimited) of diagnostics to collect. Defaults to: #{default_scope}") do |scope|
      options_scope = scope.tr(' ', '')
      unless options_scope =~ %r{^(\w+)(,\w+)*$}
        puts "Error: The scope parameter must be a comma-delimited list. Got: #{scope}"
        exit 1
      end
      options[:scope] = options_scope
    end
    opts.on('-t', '--ticket NUMBER', 'Support ticket number') do |ticket|
      options[:ticket] = ticket
    end
    opts.on('-u', '--upload', 'Upload to Puppet Support via SFTP. Requires the --ticket parameter') do
      options[:upload] = true
    end
    opts.on('--upload_disable_host_key_check', 'Disable SFTP Host Key Check. Requires the --upload parameter') do
      options[:upload_disable_host_key_check] = true
    end
    opts.on('--upload_key FILE', 'Key for SFTP. Requires the --upload parameter') do |upload_key|
      options[:upload_key] = upload_key
    end
    opts.on('--upload_user USER', 'User for SFTP. Requires the --upload parameter') do |upload_user|
      options[:upload_user] = upload_user
    end
    opts.on('-z', 'Do not delete output directory after archiving') do
      options[:z_do_not_delete_drop_directory] = true
    end
    opts.on('-h', '--help', 'Display help') do
      puts opts
      puts
      exit 0
    end
  end
  parser.parse!

  PuppetX::Puppetlabs::SupportScript::Settings.instance.configure(**options)
  support = PuppetX::Puppetlabs::SupportScript::Runner.new
  support.add_child(PuppetX::Puppetlabs::Support)

  exit support.run
end
