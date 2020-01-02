#!/opt/puppetlabs/puppet/bin/ruby

require 'date'
require 'fileutils'
require 'json'
require 'pathname'
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
  VERSION = '3.0.0.beta4'.freeze
  DOC_URL = 'https://puppet.com/docs/pe/2018.1/getting_support_for_pe.html#the-pe-support-script'.freeze

  PGP_RECIPIENT = 'FD172197'.freeze
  PGP_KEY = (<<-'EOS').freeze
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2.0.14 (GNU/Linux)

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
xfhzX6eZ+xft
=j4/z
-----END PGP PUBLIC KEY BLOCK-----
EOS

  SFTP_HOST = 'customer-support.puppetlabs.net'.freeze
  SFTP_USER = 'puppet.enterprise.support'.freeze
  SFTP_KEY = (<<-'EOS').freeze
-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----
EOS
  SFTP_KNOWN_HOSTS = (<<-'EOS').freeze
# Primary
customer-support.puppetlabs.net ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCrLB9mWc9pxVjUin3LtIRj3vMmqgv8oUKa/JAfXkRVoKgF7EYmmsjCU55pg+ZFBUD87hJ9JNKVM8TGEQ89sjnPBN6lCdKn0sc4wfVHqbh70VvX7LhQPM79eUUkvdfHcRep1VsgWrxJlKZH42X+ermWrnzE+1vz2OB/edDOjG4Ku/gh7YHFTS1VyPzf+R0q5Nl0VQvo0RHXaeVVNMLlMy5BuRQCU1+WPKKHtH+ZvzfE6/rc/CR8L4PKzcHuQN5n1bcl13hlsYr+IHMkESJyZWIHeZiKUSa7hu464Nl0LNGhDLN25bAZrqiFwiyNEhz1+v1BOhhgkFJ0vWSoKPlsqS55
customer-support.puppetlabs.net ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOwBtY6ojejMa6tl9QSAWDi2pSpTYBKldD3r6kIOJDTd2b7x99WQPFhJgWdJ76ANIolvEWI5lAkvFwMJ5SMG5Ak=
customer-support.puppetlabs.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO8GiFNutya82Ya+xeI8LWEbA2EmwVQF5gtvjsJ6s+W0
# Asia-Pacific
customer-support-syd.puppetlabs.net ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw9P+9D/QFSveyYQUEIkB0Ii9OPZpna32x05RKgMslFZWXyctXfhoFQvtE/df9TfcYA8dFZuibJZamQKwQ6VPjkbk7YdMpWbho5X9j78B7Dr74iQQKzZzLUYf4Nqrjpo+S6lHGLTA2Oxt8Hi6a7FqYqzVDR8umuetncLsPMSpjlU+veAcMIhPa5Lvw7m8dOoeiBfLs3TL+HgLMr/IUJ31QLUDIRDnB6nVBwoUU3OW+an9JksIeGyoB0kqT86nW22jFaZpzJ5YeRWvtmrlZkPjpjayPb91rKLd8ZLQGTR3Y55yArok9Q55+C74LsouNyFMKKdoa4dOh7ikhJ5wE1dU1
customer-support-syd.puppetlabs.net ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFUTiJ8+OWy3QIF2ajlOaiE7k10Ae1TP9eh4ClgNMKvrGXojaJ/qztQHGQbhsDLQT0BduJ24ow58bXebziz5JCs=
customer-support-syd.puppetlabs.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+v91GesXhPY9+hpOTqPIFlyFkMT8CrKDVNL7vFycP2
EOS

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
    # Create a Logger instance sending messages to stderr
    #
    # This method creates an instance of Ruby's standard Logger class that
    # sends messages to stderr. Formatting is kept simple and is intended
    # for consumption by humans.
    #
    # @return [Logger]
    def self.console_logger
      logger = ::Logger.new($stderr)
      # TODO: Should be configurable.
      logger.level = ::Logger::WARN
      logger.formatter = proc do |severity, datetime, progname, msg|
                           "%s: %s\n" % [severity, msg]
                         end

      logger
    end

    # Create a Logger instance sending messages to a file
    #
    # This method creates an instance of Ruby's standard Logger class that
    # sends messages to a file. DEBUG level is used to capture maximum
    # detail. Messages are formatted as JSON objects, one per line.
    #
    # @return [Logger]
    def self.file_logger(path)
      logger = ::Logger.new(path)
      # TODO: Level should be configurable.
      logger.level = ::Logger::DEBUG

      logger.formatter = proc do |severity, datetime, progname, msg|
                           {time: datetime.iso8601(3),
                            level: severity,
                            msg: msg}.to_json + "\n".freeze
                         end

      logger
    end

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
    attr_accessor :state

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

                   list: false,
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
      @state = {exit_code: 0}
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
            when :noop, :encrypt, :upload, :upload_disable_host_key_check, :list, :z_do_not_delete_drop_directory
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

    # Validate runtime configuration
    #
    # The validate method performs runtime verification of settings. This
    # method is used to ensure that file-based settings point to accssable
    # locations and that appropriate combinations of values have been provided
    # for settings that depend on each other.
    #
    # @raise [RuntimeError] raised if an invalid setting is found.
    #
    # @return [void]
    def validate
      if File.symlink?(@settings[:dir])
        raise 'The dir option cannot be a symlink: %{dir}' %
              {dir: @settings[:dir]}
      elsif (! (File.directory?(@settings[:dir]) && File.writable?(@settings[:dir])))
        raise 'The dir option is not set to a writable directory: %{dir}' %
              {dir: @settings[:dir]}
      end

      if ( @settings[:upload] && (@settings[:ticket].nil? || settings[:ticket].empty?) )
        raise 'The upload option requires a value to be specified for the ticket setting.'
      end

      if ( @settings[:upload] &&
           @settings.key?(:upload_key) && (! File.readable?(@settings[:upload_key])) )
        raise 'The upload_key option is not readable or does not exist: %{key}' %
              {key: @settings[:upload_key]}
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
    def_delegators :@config, :state

    def initialize_configable
      @config = Settings.instance
    end

    def noop?
      @config.settings[:noop]
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

  # Helper functions for gnerating diagnostic output
  #
  # The methods in this module provide an API for executing commands, returing
  # results, copying files, and otherwise generating diagnostic output. This
  # module should be included along with the {Configable} module and depends
  # on state initialized by {Runner#setup}
  module DiagnosticHelpers
    PUP_PATHS = {puppetlabs_bin: '/opt/puppetlabs/bin',
                 puppet_bin:     '/opt/puppetlabs/puppet/bin',
                 server_bin:     '/opt/puppetlabs/server/bin',
                 server_data:    '/opt/puppetlabs/server/data'}.freeze

    #===========================================================================
    # Utilities
    #===========================================================================

    # Display a message.
    def display(info = '')
      $stdout.puts(info)
    end

    # Display an error message.
    def display_warning(info = '')
      log.warn(info)
    end

    # Display an error message, and exit.
    def fail_and_exit(datum)
      log.error(datum)
      exit 1
    end

    # Execute a command line and return the result
    #
    # @param command_line [String] The command line to execute.
    # @param timeout [Integer] Amount of time, in sections, allowed for
    #   the command line to complete. Defaults to 0 which means no
    #   time limit.
    #
    # @return [String] STDOUT from the command.
    # @return [String] An empty string, if an ExecutionFailure is raised
    #   when launching the command.
    def exec_return_result(command_line, timeout = 0)
      options = { timeout: timeout }
      Facter::Core::Execution.execute(command_line, options)
    rescue Facter::Core::Execution::ExecutionFailure => e
      log.error('exec_return_result: command failed: %{command_line} with error: %{error}' %
                {command_line: command_line,
                 error: e.message})
      ''
    end

    # Execute a command line and return true or false
    #
    # @param (see #exec_return_result)
    #
    # @return [true] If the command completes with an exit code of zero.
    # @return [false] If the command completes win a non-zero exit code or
    #   an ExecutionFailure is raised.
    def exec_return_status(command_line, timeout = 0)
      options = { timeout: timeout }
      Facter::Core::Execution.execute(command_line, options)
      $?.to_i.zero?
    rescue Facter::Core::Execution::ExecutionFailure => e
      log.error('exec_return_status: command failed: %{command_line} with error: %{error}' %
                {command_line: command_line,
                 error: e.message})
      false
    end

    # Execute a command line or raise an error
    #
    # @param (see #exec_return_result)
    #
    # @return [void]
    # @raise [Facter::Core::Execution::ExecutionFailure] If the command
    #   exits with a non-zero code or a ExecutionFailure is raised during
    #   execution.
    def exec_or_fail(command_line, timeout = 0)
      options = { timeout: timeout }
      Facter::Core::Execution.execute(command_line, options)
      unless $?.to_i.zero?
        raise Facter::Core::Execution::ExecutionFailure,
              'exec_or_fail: command failed: %{command_line} with status: %{status}' %
              {command_line: command_line,
               status: $?.to_i}
      end
    end

    # Test for command existance
    #
    # @param command [String] The name of an executable
    #
    # @return [String] Expanded path to the executable if it exists and is
    #   executable.
    # @return [nil] If no executable matching `command` can be found in the
    #   `PATH`.
    def executable?(command)
      Facter::Core::Execution.which(command)
    end

    # Test for command option existence
    #
    # @param command [String] The name of a command to test
    # @param option [String] the name of an option to test
    #
    # @return [true] If the `option` can be found in the `--help` output
    #   or manpage for the command.
    # @return [false] If the `option` is not found, or an ExecutionFailure
    #   is raised.
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

    # Test whether command responds to --help
    #
    # @param command [String] The name of a command to test
    #
    # @return [true] If the command exits successfully when invoked with `--help`.
    # @return [false] If the command exits with a non-zero code when invoked
    #   with `--help`, or an ExecutionFailure is raised.
    def help_option?(command)
      command_line = "#{command} --help > /dev/null 2>&1"
      Facter::Core::Execution.execute(command_line)
      $?.to_i.zero?
    rescue Facter::Core::Execution::ExecutionFailure => e
      false
    end

    # Pretty Format JSON
    #
    # Parses a string of JSON, optionally removes blacklisted top-level keys,
    # and returns the output as a pretty-printed string.
    #
    # @param text [String] A string of JSON data.
    # @param blacklist [Array<String>] A list of keys to remove from the
    #   output.
    #
    # @return [String] Pretty printed JSON.
    # @return [String] An empty string, if parsing or generation fails.
    def pretty_json(text, blacklist = [])
      return text if text == ''
      begin
        json = JSON.parse(text)
      rescue JSON::ParserError
        log.error('pretty_json: unable to parse json')
        return ''
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
        log.error('pretty_json: unable to generate json')
        return ''
      end
    end

    # Return the value of a Puppet setting
    #
    # Values are stored in a cache after being read. Subsequent calls
    # will return the cached value.
    #
    # @param setting [String] The setting to retrieve.
    def puppet_conf(setting, section = 'main')
      state['puppet_conf'] ||= {}
      state['puppet_conf'][section] ||= {}

      cached_value = state['puppet_conf'][section].fetch(setting, nil)

      if cached_value.nil?
        value = exec_return_result("#{PUP_PATHS[:puppet_bin]}/puppet config print --section '#{section}' '#{setting}'")
        state['puppet_conf'][section][setting] = value

        value
      else
        cached_value
      end
    end

    # Request a URL using curl
    #
    # @param url [String] The URL to request.
    # @param headers [Hash{String => String}] A hash of headers to add to
    #   the request where the key is the header name and the value is the
    #   header value.
    # @param options [Hash] A hash of options where the key is the name
    #   of a `curl` long flag and the value is the value to pass with the
    #   flag.
    #
    # @return [String] The body returned by the request.
    def curl_url(url, headers: {}, **options)
      headers = headers.reduce('') {|m, (k,v)| m += " -H '#{k}: #{v}'"}
      opts = options.reduce('--insecure --silent --show-error --connect-timeout 5 --max-time 60') {|m, (k,v)| m += " --#{k} '#{v}'"}

      exec_return_result("#{PUP_PATHS[:puppet_bin]}/curl #{headers} #{opts} '#{url}'")
    end

    # Request a URL using the agent's certificate
    #
    # @see curl_url
    def curl_cert_auth(url, **options)
      cert = puppet_conf('hostcert')
      key = puppet_conf('hostprivkey')

      unless File.readable?(cert)
        log.error('unable to read agent certificate for curl: %{cert}' %
                  {cert: cert})
        return ''
      end

      unless File.readable?(key)
        log.error('unable to read agent private key for curl: %{key}' %
                  {key: key})
        return ''
      end

      options[:key] = key
      options[:cert] = cert

      curl_url(url, **options)
    end

    # Return package manager used by the OS executing the script
    #
    # @return [String] a string giving the name of the executable used
    #   to manage packages
    # @return [nil] for unknown operating systems
    def pkg_manager
      return state[:platform_packaging] if state.key?(:platform_packaging)

      os = Facter.value('os')
      pkg_manager = case os['family'].downcase
                    when 'redhat', 'suse'
                      'rpm'
                    when 'debian'
                      'dpkg'
                    else
                      log.error('Unknown packaging system for operating system "%{os_name}" and famliy "%{os_family}"' %
                                {os_name: os['name'],
                                 os_family: os['family']})
                      # Mark run as failed.
                      state[:exit_code] = 1
                      nil
                    end

      state[:platform_packaging] = pkg_manager
      pkg_manager
    end

    # Return a text report of installed packages that match a regex
    #
    # @return [String] a human-readble report of matching packages
    #   along with a list of any changes made to files managed by
    #   the package
    def query_packages_matching(regex)
      result = ''
      acsiibar = '=' * 80
      case pkg_manager
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
        log.warn('query_packages_matching: unable to list packages: no package manager for this OS')
        result = 'no package manager for this OS'
      end
      result
    end

    # Query a package and report if it is installed
    #
    # @return [Boolean] a boolean value indicating whether the package is
    #   installed.
    def package_installed?(package)
      status = false
      state[:installed_packages] ||= {}
      return state[:installed_packages][package] if state[:installed_packages].key?(package)

      case pkg_manager
      when 'rpm'
        status = exec_return_result(%(rpm --query --info #{package})) =~ %r{Version}
      when 'dpkg'
        status = exec_return_status(%(dpkg-query  --show #{package}))
      else
        log.warn('package_installed: unable to query package for platform: no package manager for this OS')
      end

      state[:installed_packages][package] = status
      status
    end

    #===========================================================================
    # Output
    #===========================================================================

    # Execute a command and append the results to an output file
    #
    # @param command_line [String] Command line to execute.
    # @param dst [String] Destination directory for output.
    # @param file [String] File under `dst` where output should be appended.
    # @param options [Hash] A Hash of options.
    # @option options timeout [Integer] Optional number of seconds to allow for
    #   command execution. Defaults to 0 which disables the timeout.
    # @option options stderr [String, nil] An optional additional file to send
    #   stderr to. Stderr is merged into stdout if not provided.
    #
    # @return [true] If the command completes successfully.
    # @return [false] If the command cannot be found, exits with a non-zero code,
    #   or there is an error creating the output path.
    def exec_drop(command_line, dst, file, options = {})
      default_options = {
        'timeout' => 0,
        'stderr' => nil
      }
      options = default_options.merge(options)

      command = command_line.split(' ')[0]
      dst_file_path = File.join(dst, file)
      if options['stderr'].nil?
        stderr_dst = '2>&1'
      else
        stderr_dst = "2>> '#{File.join(dst, options['stderr'])}'"
      end
      command_line = %(#{command_line} #{stderr_dst} >> '#{dst_file_path}')
      unless executable?(command)
        log.debug('exec_drop: command not found: %{command} cannot execute: %{command_line}' %
                  {command: command,
                   command_line: command_line})
        return false
      end
      log.debug('exec_drop: appending output of: %{command_line} to: %{dst_file_path}' %
                {command_line: command_line,
                 dst_file_path: dst_file_path})

      if noop?
        display(' (noop) Collecting output of: %{command_line}' %
                {command_line: command_line})
        return
      else
        display(' ** Collecting output of: %{command_line}' %
                {command_line: command_line})
      end

      return false unless create_path(dst)

      exec_return_status(command_line, options['timeout'])
    end

    # Append data to an output file
    #
    # @param data [String] Data to append.
    # @param dst [String] Destination directory for output.
    # @param file [String] File under `dst` where data should be appended.
    #
    # @return [true] If data output succeeds.
    # @return [false] If there is an error creating the output path.
    def data_drop(data, dst, file)
      dst_file_path = File.join(dst, file)
      log.debug('data_drop: appending to: %{dst_file_path}' %
                {dst_file_path: dst_file_path})

      if noop?
        display(' (noop) Adding data to: %{dst_file_path}' %
                {dst_file_path: dst_file_path})
        return
      else
        display(' ** Adding data to: %{dst_file_path}' %
                {dst_file_path: dst_file_path})
      end

      return false unless create_path(dst)

      File.open(dst_file_path, 'a') { |file| file.puts(data) }
      true
    end

    # Compress file to a destination directory
    #
    # @param src [String] File to output.
    # @param dst [String] Destination directory for output.
    # @param options [Hash] A Hash of options.
    # @option options recreate_parent_path [Boolean] Whether to re-create parent
    #   directories of the `src` underneath `dst`. Defaults to `true`.
    #
    # @return [true] If the compress command succeeds.
    # @return [false] If the compress command exits with an error,
    #   or if there is an error creating the output path.
    def compress_drop(src, dst, options = {})
      default_options = { 'recreate_parent_path' => true }
      options = default_options.merge(options)

      log.debug('compress_drop: compressing: %{src} to: %{dst} with options: %{options}' %
                {src: src,
                 dst: dst,
                 options: options})

      unless File.readable?(src)
        log.debug('compress_drop: source not readable: %{src}' %
                  {src: src})
        return false
      end

      if noop?
        display(' (noop) Compressing: %{src}' %
                {src: src})
        return
      else
        display(' ** Compressing: %{src}' %
                {src: src})
      end

      if options['recreate_parent_path']
        dst_file = File.join(dst, "#{src}.gz")
        dst = File.dirname(dst_file)
      else
        dst_file = File.join(dst, "#{File.basename(src)}.gz")
      end
      command_line = %(gzip -c '#{src}' > '#{dst_file}' && touch -c -r '#{src}' '#{dst_file}')

      return false unless create_path(dst)

      exec_return_status(command_line)
    end

    # Copy directories or files to a destination directory
    #
    # @param src [String] Source directory for output.
    # @param dst [String] Destination directory for output.
    # @param options [Hash] A Hash of options.
    # @option options recreate_parent_path [Boolean] Whether to re-create parent
    #   directories of files in `src` underneath `dst`. Defaults to `true`.
    # @option options cwd [String, nil] Change to the directory given by `cwd`
    #   before copying `src`s as relative paths.
    # @option options age [Integer] Specifies maximum age, in days, to filter list
    #   of copied files.
    #
    # @return [true] If the copy command succeeds.
    # @return [false] If the copy command exits with an error,
    #   or if there is an error creating the output path.
    def copy_drop(src, dst, options = {})
      default_options = {
        'recreate_parent_path' => true,
        'cwd' => nil,
        'age' => nil
      }
      options = default_options.merge(options)

      log.debug('copy_drop: copying: %{src} to: %{dst} with options: %{options}' %
                {src: src,
                 dst: dst,
                 options: options})

      expanded_path = File.join(options['cwd'].to_s, src)
      unless File.readable?(expanded_path)
        log.debug('copy_drop: source not readable: %{src}' %
                  {src: expanded_path})
        return false
      end

      if noop?
        display(' (noop) Copying: %{src}' %
                {src: expanded_path})
        return
      else
        display(' ** Copying: %{src}' %
                {src: expanded_path})
      end

      parents_option = options['recreate_parent_path'] ? ' --parents' : ''
      # NOTE: Facter's execution expands the path of the first command,
      #       which breaks `cd`. See FACT-2054.
      cd_option = options['cwd'].nil? ? '' : "true && cd '#{options['cwd']}' && "

      if options['age'].nil?
        recursive_option = File.directory?(src) ? ' --recursive' : ''
        command_line = %(#{cd_option}cp --dereference --preserve #{parents_option} #{recursive_option} '#{src}' '#{dst}')
      else
        age_filter = (options['age'].is_a?(Integer) && (options['age'] > 0)) ? " -mtime -#{options['age']}" : ''
        command_line = %(#{cd_option}find '#{src}' -type f #{age_filter} -exec cp --dereference --preserve #{parents_option} --target-directory '#{dst}' {} +)
      end

      return false unless create_path(dst)

      exec_return_status(command_line)
    end

    # Recursively create a directory
    #
    # @param path [String] Path to the directory to create.
    # @param options [Hash] A Hash of FileUtils.mkdir_p options.
    #
    # @return [true] If directory exists or creation is successful.
    # @return [false] If directory creation fails.
    def create_path(path, options = {})
      default_options = { :noop => noop? }
      options = default_options.merge(options)
      FileUtils.mkdir_p(path, **options)
      true
    rescue => e
      log.error("%{exception_class} raised when creating directory: %{message}\n\t%{backtrace}" %
                {exception_class: e.class,
                 message: e.message,
                 backtrace: e.backtrace.join("\n\t")})
      false
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
    include DiagnosticHelpers

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
                         [@parent.name, @name].join('.')
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
    include DiagnosticHelpers

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
                         [@parent.name, @name].join('.')
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
        log.info('starting evaluation of: %{name}' %
                 {name: child.name})

        if child.class < Check
          display('Evaluating check: %{name}' %
                  {name: child.name})
        else
          display("\nEvaluating scope: %{name}" %
                  {name: child.name})
        end

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

    # Recursively print a description of each child to stdout
    #
    # @return [void]
    def describe
      @children.each do |child|
        next unless child.suitable?

        if child.enabled?
          display child.name
        else
          display child.name + ' (opt-in with --enable)'
        end

        if child.is_a?(Scope)
          child.describe
        end
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
        begin
          child = klass.new(self, **opts)
        rescue => e
          log.error("%{exception_class} raised when initializing %{klass} in scope '%{scope}': %{message}\n\t%{backtrace}" %
                    {exception_class: e.class,
                     klass: klass.name,
                     scope: self.name,
                     message: e.message,
                     backtrace: e.backtrace.join("\n\t")})
          next
        end

        child.enabled = false if (not self.enabled?)

        # Handle disabling things that do not appear in the `only` list
        if (not settings[:only].empty?) && child.enabled?
          # Disable children unless they are explicitly enabled, or one of
          # their parents is explicitly enabled.
          child.enabled = false unless enable_list.any? {|e| child.name.start_with?(e)}
        end

        # Handle enabling things that appear in the `enabled` or `only` lists
        if (klass < Scope)
          # Enable Scopes if they are explicitly enabled, or one of their
          # children is explicitly enabled.
          child.enabled = true if enable_list.any? {|e| e.start_with?(child.name)}
        elsif (klass < Check)
          # Enable Checks if they are explicitly enabled.
          child.enabled = true if enable_list.include?(child.name)
        end

        # Handle the `disable` list
        child.enabled = false if settings[:disable].include?(child.name)

        child
      end

      # Remove any children that failed to initialize
      @children.compact!
    end
  end

  # Gather basic diagnostics
  #
  # This check produces:
  #
  #   - A metadata.json file that contains the version of the support
  #     script that is running, the Puppet ticket number, if supplied,
  #     and the time at which the script was run.
  class Check::BaseStatus < Check
    # The base check is always suitable
    def suitable?
      true
    end

    # The base check is always enabled
    def enabled?
      true
    end

    def run
      metadata = JSON.pretty_generate(version: PuppetX::Puppetlabs::SupportScript::VERSION,
                                      ticket: settings[:ticket],
                                      timestamp: state[:start_time].iso8601(3))
      metadata_file = File.join(state[:drop_directory], 'metadata.json')

      data_drop(metadata, state[:drop_directory], 'metadata.json')
    end
  end

  # Base scope which includes all other scopes
  class Scope::Base < Scope
    # The base scope is always suitable
    def suitable?
      true
    end

    # The base scope is always enabled
    def enabled?
      true
    end

    self.add_child(Check::BaseStatus, name: 'base-status')
  end

  # Gather operating system configuration
  #
  # This check gathers:
  #
  #   - A copy of /etc/hosts
  #   - A copy of /etc/nsswitch.conf
  #   - A copy of /etc/resolv.conf
  #   - Configuration for the apt, yum, and dnf package managers
  #   - The operating system version
  #   - The umask in effect
  #   - The status of SELinux
  #   - A list of configured network interfaces
  #   - A list of configured firewall rules
  #   - A list of loaded firewall kernel modules
  class Check::SystemConfig < Check
    CONF_FILES = ['apt/apt.conf.d',
                  'apt/sources.list.d',
                  'dnf/dnf.conf',
                  'hosts',
                  'nsswitch.conf',
                  'os-release',
                  'resolv.conf',
                  'yum.conf',
                  'yum.repos.d'].map { |f| File.join('/etc', f) }

    def run
      output_directory = File.join(state[:drop_directory], 'system')
      return false unless create_path(output_directory)

      exec_drop('lsb_release -a',       output_directory, 'lsb_release.txt')
      exec_drop('sestatus',             output_directory, 'selinux.txt')
      exec_drop('umask',                output_directory, 'umask.txt')
      exec_drop('uname -a',             output_directory, 'uname.txt')

      CONF_FILES.each do |file|
        copy_drop(file, output_directory)
      end

      output_directory = File.join(state[:drop_directory], 'networking')
      return false unless create_path(output_directory)

      data_drop(Facter.value('fqdn'), output_directory, 'hostname_output.txt')
      exec_drop('ifconfig -a',        output_directory, 'ifconfig.txt')
      exec_drop('iptables -L',        output_directory, 'ip_tables.txt')
      exec_drop('ip6tables -L',       output_directory, 'ip_tables.txt')

      unless executable?('iptables')
        exec_drop('lsmod | grep ip', output_directory, 'ip_modules.txt')
      end

      # Create symlinks for compatibility with SOScleaner
      #   https://github.com/RedHatGov/soscleaner
      FileUtils.mkdir(File.join(state[:drop_directory], 'etc'), :noop => noop?)
      FileUtils.ln_s('networking/hostname_output.txt',
                      File.join(state[:drop_directory], 'hostname'), :noop => noop?)
      FileUtils.ln_s('../system/etc/hosts',
                      File.join(state[:drop_directory], 'etc/hosts'), :noop => noop?)
    end
  end

  # Gather operating system logs
  #
  # This check gathers:
  #
  #   - A copy of the system log
  #   - A copy of the kernel log
  class Check::SystemLogs < Check
    def run
      output_directory = File.join(state[:drop_directory], 'logs')
      return false unless create_path(output_directory)

      compress_drop('/var/log/messages', output_directory, { 'recreate_parent_path' => false })
      compress_drop('/var/log/syslog', output_directory, { 'recreate_parent_path' => false })
      compress_drop('/var/log/system', output_directory, { 'recreate_parent_path' => false })

      if documented_option?('dmesg', '--ctime')
        if documented_option?('dmesg', '--time-format')
          exec_drop('dmesg --ctime --time-format iso', output_directory, 'dmesg.txt')
        else
          exec_drop('dmesg --ctime', output_directory, 'dmesg.txt')
        end
      else
        exec_drop('dmesg', output_directory, 'dmesg.txt')
      end
    end
  end

  # Gather operating system diagnostics
  #
  # This check gathers:
  #
  #   - A list of variables set in the environment
  #   - A list of running processes
  #   - A list of enabled services
  #   - The uptime of the system
  #   - A list of established network connections
  #   - NTP status
  #   - The IP address and hostname of the node according to DNS
  #   - Disk usage
  #   - RAM usage
  class Check::SystemStatus < Check
    def run
      output_directory = File.join(state[:drop_directory], 'system')
      return false unless create_path(output_directory)

      exec_drop('env',                  output_directory, 'env.txt')
      exec_drop('ps -aux',              output_directory, 'ps_aux.txt')
      exec_drop('ps -ef',               output_directory, 'ps_tree.txt')
      exec_drop('chkconfig --list',     output_directory, 'services.txt')
      exec_drop('svcs -a',              output_directory, 'services.txt')
      exec_drop('systemctl list-units', output_directory, 'services.txt')
      exec_drop('uptime',               output_directory, 'uptime.txt')

      output_directory = File.join(state[:drop_directory], 'networking')
      return false unless create_path(output_directory)

      exec_drop('netstat -anptu',     output_directory, 'ports.txt')
      exec_drop('ntpq -p',            output_directory, 'ntpq_output.txt')

      unless noop?
        command = %[ping -t1 -c1 '#{Facter.value('fqdn')}'|head -n1|tr -ds '()' ' '|cut -d ' ' -f3]
        ip_address = exec_return_result(command)

        unless ip_address.empty?
          data_drop(ip_address, output_directory, 'guessed_ip_address.txt')
          exec_drop("getent hosts '#{ip_address}'", output_directory, 'mapped_hostname_from_guessed_ip_address.txt')
        end
      end

      output_directory = File.join(state[:drop_directory], 'resources')
      return false unless create_path(output_directory)

      exec_drop('df -h',   output_directory, 'df_output.txt')
      exec_drop('df -i',   output_directory, 'df_output.txt')
      exec_drop('df -k',   output_directory, 'df_inodes_output.txt')
      exec_drop('free -h', output_directory, 'free_mem.txt')
    end
  end

  # Scope which collects diagnostics from the operating system
  #
  # @todo Should confine to *NIX and have a seperate scope for Windows.
  class Scope::System < Scope
    Scope::Base.add_child(self, name: 'system')

    self.add_child(Check::SystemConfig, name: 'config')
    self.add_child(Check::SystemLogs, name: 'logs')
    self.add_child(Check::SystemStatus, name: 'status')

    def setup(**options)
      # TODO: Many diagnostics contained here are also applicable to Solaris
      #       AIX, and macOS, but should be reviewed and possibly split out
      #       to a separate set of checks or scope. Windows needs its own
      #       things.
      confine(kernel: 'linux')
    end
  end

  # A generic check for collecting files
  #
  # This check gathers a list of files and directories, subject to limits on
  # age and disk space. The file list may include glob expressions which are
  # expanded.
  class Check::GatherFiles < Check
    def setup(**options)
      # TODO: assert that @files is a match for
      # Array[Struct[{from    => Optional[String[1]],
      #               copy    => Array[String[1], 1],
      #               to      => String[1],
      #               max_age => Optional[Integer]}]]
      @files = options[:files]

      # TODO: Solaris and AIX do `df` in their own very, very special ways.
      #       `df` and `find -ls` on non-Linux returns 512 byte blocks instead of 1024.
      #       The copy_drop* functions assume flags that are specific to
      #       GNU `cp`.
      confine(kernel: 'linux')
    end

    def run
      @files.map! do |batch|
        result = batch.dup
        result[:max_age] ||= settings[:log_age]
        # Resolve any globs in the copy array to a single list of files.
        result[:copy] = if batch[:from].nil?
                          Dir.glob(result[:copy])
                        else
                          base = Pathname.new(batch[:from])
                          absolute_paths = result[:copy].map {|p| base.join(p) }
                          Pathname.glob(absolute_paths).map {|p| p.relative_path_from(base).to_s }
                        end
        result[:to] = File.join(state[:drop_directory], result[:to])

        result
      end

      return unless disk_available?

      @files.each do |batch|
        batch[:copy].each do |src|
          copy_drop(src, batch[:to], { 'age' => batch[:max_age], 'cwd' => batch[:from] })
        end
      end
    end

    # Check there is enough disk space to copy the logs
    #
    # @return [true, false] A boolean value indicating whether enough
    #   space is available.
    def disk_available?
      return true if noop?

      df_output = exec_return_result("df '#{state[:drop_directory]}'|tail -n1|tr -s ' '|cut -d' ' -f4").chomp
      free = Integer(df_output) rescue nil

      if free.nil?
        log.error('Could not determine disk space available on %{drop_dir}, df returned: %{output}'%
                  {drop_dir: state[:drop_directory],
                   output: df_output})
        return false
      end

      required = 0
      @files.each do |batch|
        # NOTE: Facter's execution expands the path of the first command,
        #       which breaks `cd`. See FACT-2054.
        cd_option = batch[:from].nil? ? '' : "true && cd '#{batch[:from]}' && "
        age_filter = (batch[:max_age].is_a?(Integer) && (batch[:max_age] > 0)) ? " -mtime -#{batch[:max_age]}" : ''
        batch[:copy].each do |f|
          used = exec_return_result("#{cd_option}find '#{f}' -type f #{age_filter} -ls|awk '{total=total+$2}END{print total}'").chomp
          required += Integer(used) unless used.empty?
        end
      end

      # We require double the free space as we copy the file, then copy it
      # again into a compressed archive.
      if ((required * 2) > free)
        log.error("Not enough free disk space in %{output_dir} to gather %{name}.\nAvailable: %{available} MB, Required: %{required} MB" %
                  {output_dir: settings[:dir],
                   name: self.name,
                   # Convert 1024 byte blocks to MB
                   available: (free) / 1024,
                   required: (required * 2) / 1024})

        false
      else
        true
      end
    end
  end

  # A check for gathering log files and journalctl data
  class Check::ServiceLogs < Check::GatherFiles
    def setup(**options)
      super

      @services = options[:services]
      if @services.nil? || (! @services.is_a?(Array))
        raise ArgumentError, 'Check::ServiceLogs must be initialized with a list of strings for the services: parameter.'
      end
    end

    def run
      super

      if (! noop?) && executable?('journalctl')
        age_filter = (settings[:log_age].is_a?(Integer) && (settings[:log_age] > 0)) ? " --since '#{settings[:log_age]} days ago'" : ''

        @services.each do |service|
          log_directory = File.join(state[:drop_directory], 'logs', service.sub('pe-', ''))
          next unless create_path(log_directory)

          exec_drop("journalctl --full --output=short-iso --unit='#{service}.service' #{age_filter}", log_directory, "#{service}-journalctl.log")
        end
      end
    end
  end

  # A check for gathering configuration files with redaction
  class Check::ConfigFiles < Check::GatherFiles
    def run
      super

      unless noop?
        @files.each do |batch|
          batch[:copy].each do |file|
            exec_return_result("true && cd '#{batch[:to]}' && find '#{file}' -type f -exec sed --in-place '/password/d' {} +")
          end
        end
      end
    end
  end

  # A check for gathering runtime information about a set of services
  class Check::ServiceStatus < Check
    def setup(**options)
      @services = options[:services]
      if @services.nil? || (! @services.is_a?(Array))
        raise ArgumentError, 'Check::ServiceStatus must be initialized with a list of strings for the services: parameter.'
      end

      @service_pids = {}

      # Everything here is specific to systemd or sysvinit
      confine(kernel: 'linux')
    end

    def run
      output_directory = File.join(state[:drop_directory], 'system')
      return false unless create_path(output_directory)

      if (! noop?) && executable?('systemctl')
        @services.each do |service|
          exec_drop("systemctl status '#{service}.service'", output_directory, 'systemctl-status.txt')
        end
      end

      unless noop?
        @services.each do |service|
          if executable?('systemctl')
            # SystemD makes this ridiculously easy.
            pid = exec_return_result("systemctl show -p MainPID '#{service}.service'|cut -d= -f2").chomp
            pid = Integer(pid) rescue nil
            # SystemD returns MainPID=0 if the service is stopped or does
            # not exist.
            pid = nil if (pid == 0)

            @service_pids[service] = pid
          else
            pidfile = case service
                      when 'puppet'
                        # puppet is a special snowflake
                        '/var/run/puppetlabs/agent.pid'
                      when 'pxp-agent'
                        # pxp-agent is also a special snowflake
                        '/var/run/puppetlabs/pxp-agent.pid'
                      when 'pe-postgresql'
                        # pe-postgresql is just waaaaayyy too special without SystemD,
                        # skip it for now.
                        next
                      else
                        service_name = service.sub('pe-', '')
                        "/var/run/puppetlabs/#{service_name}/#{service_name}.pid"
                      end

            if File.readable?(pidfile)
              pid = Integer(File.read(pidfile).chomp) rescue nil
              pid_alive = unless pid.nil?
                            Process.kill(0, pid) rescue nil
                          end

              @service_pids[service] = pid if pid_alive
            end
          end

          next if @service_pids[service].nil?

          proc_directory = File.join(output_directory, 'proc', service)
          return false unless create_path(proc_directory)

          ['cmdline','limits','environ'].each do |procfile|
            copy_drop("/proc/#{@service_pids[service]}/#{procfile}", proc_directory, { 'recreate_parent_path' => false })
          end
          data_drop(File.readlink("/proc/#{@service_pids[service]}/exe"), proc_directory, 'exe')
          FileUtils.chmod_R('u+wX', proc_directory)

          if executable?('systemctl')
            # Grab CGroup settings for the service.
            ['memory','cpu','blkio','devices','pids','systemd'].each do |fs|
              copy_drop("/sys/fs/cgroup/#{fs}/system.slice/#{service}.service/", output_directory)
            end
            FileUtils.chmod_R('u+wX', "#{output_directory}/sys") if File.exist?("#{output_directory}/sys")
          end
        end
      end
    end
  end

  # Check the status of components in the puppet-agent package
  #
  # This check gathers:
  #
  #   - Facter output and debug-level logs
  #   - A list of gems installed in the Puppet Ruby environment
  #   - Whether Puppet's configured server hostname responds to a ping
  #   - A copy of classes.txt, graphs/, last_run_summary.yaml, and
  #     resources.txt from Puppet's statedir.
  #   - A listing of files present in the following directories:
  #     * /etc/puppetlabs
  #     * /var/log/puppetlabs
  #     * /opt/puppetlabs
  #   - A listing of Puppet and PE packages installed on the system
  #     along with verification output for each.
  class Check::PuppetAgentStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')
      sys_directory = File.join(state[:drop_directory], 'system')
      net_directory = File.join(state[:drop_directory], 'networking')
      find_directory = File.join(state[:drop_directory], 'enterprise', 'find')

      exec_drop("#{PUP_PATHS[:puppet_bin]}/facter --puppet --json --debug", sys_directory, 'facter_output.json', stderr: 'facter_output.debug.log')
      exec_drop("#{PUP_PATHS[:puppet_bin]}/gem list --local", ent_directory, 'puppet_gems.txt')

      unless noop? || (puppet_server = puppet_conf('server', 'agent')).empty?
        exec_drop("ping -c 1 #{puppet_server}", net_directory, 'puppet_ping.txt')
      end

      unless (statedir = puppet_conf('statedir', 'agent')).empty?
        output_dir = File.join(state[:drop_directory], 'enterprise', 'state')

        ['classes.txt', 'graphs/', 'last_run_summary.yaml', 'resources.txt'].each do |file|
          copy_drop(file, output_dir, { 'age' => -1, 'cwd' => statedir })
        end
      end

      ['/etc/puppetlabs', '/var/log/puppetlabs', '/opt/puppetlabs'].each do |path|
        drop_name = path.gsub('/','_') + '.txt.gz'
        exec_drop("find '#{path}' -ls | gzip -f9", find_directory, drop_name)
      end

      data_drop(query_packages_matching('^pe-|^puppet'), ent_directory, 'puppet_packages.txt')
    end
  end

  # Scope which collects diagnostics related to the Puppet service
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for puppet,
  #     facter, and pxp-agent
  #   - Logs from /var/log/puppetlabs for puppet and pxp-agent
  class Scope::Puppet < Scope
    def setup(**options)
      confine { package_installed?('puppet-agent') }
    end

    Scope::Base.add_child(self, name: 'puppet')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['facter/facter.conf',
                                   'puppet/device.conf',
                                   'puppet/hiera.yaml',
                                   'puppet/puppet.conf',
                                   'pxp-agent/modules/',
                                   'pxp-agent/pxp-agent.conf'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['puppet/',
                                   'pxp-agent/'],
                            to: 'logs'}],
                   services: ['puppet', 'pxp-agent'])
    self.add_child(Check::PuppetAgentStatus,
                   name: 'status',
                   services: ['puppet', 'pxp-agent'])
  end

  # Check the status of components related to Puppet Server
  #
  # This check gathers:
  #
  #   - A list of certificates issued by the Puppet CA
  #   - A list of gems installed for use by Puppet Server
  #   - Output from the `status/v1/services` API
  #   - Output from the `puppet/v3/environment_modules` API
  #   - Output from the `puppet/v3/environments` API
  #   - environment.conf and hiera.yaml from each environment
  #   - The disk space used by Code Manager cache, storage, client,
  #     and staging directories.
  #   - The output of `r10k deploy display`
  #   - The disk space used by the server's File Bucket
  class Check::PuppetServerStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')
      res_directory = File.join(state[:drop_directory], 'resources')

      if File.directory?(puppet_conf('cadir', 'master'))
        if SemanticPuppet::Version.parse(Puppet.version) >= SemanticPuppet::Version.parse('6.0.0')
          exec_drop("#{PUP_PATHS[:server_bin]}/puppetserver ca list --all", ent_directory, 'certs.txt')
        else
          exec_drop("#{PUP_PATHS[:puppet_bin]}/puppet cert list --all", ent_directory, 'certs.txt')
        end
      end

      exec_drop("#{PUP_PATHS[:server_bin]}/puppetserver gem list --local", ent_directory, 'puppetserver_gems.txt')

      data_drop(curl_cert_auth('https://127.0.0.1:8140/status/v1/services?level=debug'), ent_directory, 'puppetserver_status.json')
      data_drop(curl_cert_auth('https://127.0.0.1:8140/puppet/v3/environment_modules'), ent_directory, 'modules.json')

      # Collect data using environments from the puppet/v3/environments endpoint.
      # Equivalent to puppetserver_environments() in puppet-enterprise-support.sh
      puppetserver_environments_json = curl_cert_auth('https://127.0.0.1:8140/puppet/v3/environments')
      data_drop(puppetserver_environments_json, ent_directory, 'puppetserver_environments.json')
      puppetserver_environments = begin
                                    JSON.parse(puppetserver_environments_json)
                                  rescue JSON::ParserError
                                    log.error('PuppetServerStatus: unable to parse puppetserver_environments_json')
                                    {}
                                  end

      puppetserver_environments['environments'].keys.each do |environment|
        environment_manifests = puppetserver_environments['environments'][environment]['settings']['manifest']
        environment_directory = File.dirname(environment_manifests)
        environment_drop_directory = File.join(ent_directory, 'etc/puppetlabs/code/environments', environment)

        copy_drop('environment.conf', environment_drop_directory, { 'recreate_parent_path' => false, 'cwd' => environment_directory })
        copy_drop('hiera.yaml', environment_drop_directory, { 'recreate_parent_path' => false, 'cwd' => environment_directory })
      end unless puppetserver_environments.empty?

      r10k_config = '/opt/puppetlabs/server/data/code-manager/r10k.yaml'
      if File.exist?(r10k_config)
        # Code Manager and File Sync diagnostics
        code_staging_directory = '/etc/puppetlabs/code-staging'
        filesync_directory = '/opt/puppetlabs/server/data/puppetserver/filesync'
        code_manager_cache = '/opt/puppetlabs/server/data/code-manager'
        exec_drop("du -h --max-depth=1 #{code_staging_directory}", res_directory, 'code_staging_sizes_from_du.txt') if File.directory?(code_staging_directory)
        exec_drop("du -h --max-depth=1 #{filesync_directory}", res_directory, 'filesync_sizes_from_du.txt') if File.directory?(filesync_directory)
        exec_drop("du -h --max-depth=1 #{code_manager_cache}", res_directory, 'r10k_cache_sizes_from_du.txt') if File.directory?(code_manager_cache)
        exec_drop("#{PUP_PATHS[:puppet_bin]}/r10k deploy display -p --detail -c #{r10k_config}", ent_directory, 'r10k_deploy_display.txt')
      end

      # Collect Puppet Enterprise File Bucket diagnostics.
      filebucket_directory = '/opt/puppetlabs/server/data/puppetserver/bucket'
      exec_drop("du -sh #{filebucket_directory}", res_directory, 'filebucket_size_from_du.txt') if File.directory?(filebucket_directory)
    end
  end

  # Scope which collects diagnostics related to the PuppetServer service
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for puppet,
  #     puppetserver, and r10k
  #   - Logs from /var/log/puppetlabs for puppetserver and r10k
  #   - Metrics from /opt/puppetlabs/puppet-metrics-collector
  #     for puppetserver
  class Scope::PuppetServer < Scope
    def setup(**options)
      confine { package_installed?('pe-puppetserver') }
    end

    Scope::Base.add_child(self, name: 'puppetserver')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['code/hiera.yaml',
                                   'puppet/auth.conf',
                                   'puppet/autosign.conf',
                                   'puppet/classfier.yaml',
                                   'puppet/fileserver.conf',
                                   'puppet/hiera.yaml',
                                   'puppet/puppet.conf',
                                   'puppet/puppetdb.conf',
                                   'puppet/routes.yaml',
                                   'puppetserver/bootstrap.cfg',
                                   'puppetserver/code-manager-request-logging.xml',
                                   'puppetserver/conf.d/',
                                   'puppetserver/logback.xml',
                                   'puppetserver/request-logging.xml',
                                   'r10k/r10k.yaml'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1},
                            {from: '/opt/puppetlabs/server/data/code-manager',
                             copy: ['r10k.yaml'],
                             to: 'enterprise/etc/puppetlabs/puppetserver',
                             max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['puppetserver/',
                                   'r10k/'],
                            to: 'logs'}],
                   services: ['pe-puppetserver'])
    self.add_child(Check::GatherFiles,
                   name: 'metrics',
                   files: [{from: '/opt/puppetlabs/puppet-metrics-collector',
                            copy: ['puppetserver/'],
                            to: 'metrics'}])
    self.add_child(Check::PuppetServerStatus,
                   name: 'status',
                   services: ['pe-puppetserver'])
  end

  # Check the status of components related to PuppetDB
  #
  # This check gathers:
  #
  #   - Output from the `status/v1/services` API
  #   - Output from the `pdb/admin/v1/summary-stats` API
  #   - A list of certnames for nodes that PuppetDB considers to be active
  class Check::PuppetDBStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')

      # Out of all PE services, PuppetDB occasionally conflicts with other
      # installed software due to its use of ports 8080 and 8081.
      #
      # So, we check to see if an alternate port has been configured.
      puppetdb_port = exec_return_result(%(cat /etc/puppetlabs/puppetdb/conf.d/jetty.ini | tr -d ' ' | grep --extended-regexp '^port=[[:digit:]]+$' | cut -d= -f2))
      puppetdb_port = '8080' if puppetdb_port.empty?

      data_drop(curl_url("http://127.0.0.1:#{puppetdb_port}/status/v1/services?level=debug"), ent_directory, 'puppetdb_status.json')
      data_drop(curl_url("http://127.0.0.1:#{puppetdb_port}/pdb/admin/v1/summary-stats"), ent_directory, 'puppetdb_summary_stats.json')
      data_drop(curl_url("http://127.0.0.1:#{puppetdb_port}/pdb/query/v4",
                         request: 'GET',
                         'data-urlencode': 'query=nodes[certname] {deactivated is null and expired is null}'),
                ent_directory, 'puppetdb_nodes.json')
    end
  end

  # Scope which collects diagnostics related to the PuppetDB service
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for puppetdb
  #   - Logs from /var/log/puppetlabs for puppetdb
  #   - Metrics from /opt/puppetlabs/puppet-metrics-collector
  #     for puppetdb
  class Scope::PuppetDB < Scope
    def setup(**options)
      confine { package_installed?('pe-puppetdb') }
    end

    Scope::Base.add_child(self, name: 'puppetdb')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['puppetdb/bootstrap.cfg',
                                   'puppetdb/certificate-whitelist',
                                   'puppetdb/conf.d/',
                                   'puppetdb/logback.xml',
                                   'puppetdb/request-logging.xml'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['puppetdb/'],
                            to: 'logs'}],
                   services: ['pe-puppetdb'])
    self.add_child(Check::GatherFiles,
                   name: 'metrics',
                   files: [{from: '/opt/puppetlabs/puppet-metrics-collector',
                            copy: ['puppetdb/'],
                            to: 'metrics'}])
    self.add_child(Check::PuppetDBStatus,
                   name: 'status',
                   services: ['pe-puppetdb'])
  end

  # A Check that gathers miscellaneous PE status info
  #
  # This check gathers:
  #
  #   - Status information for the entire PE install
  #   - Current tuning settings
  #   - Recommended tuning settings
  class Check::PeStatus < Check
    def run
      ent_directory = File.join(state[:drop_directory], 'enterprise')

      exec_drop("#{PUP_PATHS[:puppetlabs_bin]}/puppet-infrastructure status --format json", ent_directory, 'pe_infra_status.json')
      exec_drop("#{PUP_PATHS[:puppetlabs_bin]}/puppet-infrastructure tune",                 ent_directory, 'puppet_infra_tune.txt')
      exec_drop("#{PUP_PATHS[:puppetlabs_bin]}/puppet-infrastructure tune --current",       ent_directory, 'puppet_infra_tune_current.txt')
    end
  end

  # A Check that gathers files related to PE file sync state
  #
  # This check uses Check::GatherFiles to collect a copy of directories
  # related to File Sync. It is disabled by default due to the high
  # probablility that these directories contain sensitive data.
  class Check::PeFileSync < Check::GatherFiles
    def setup(**options)
      super(**options)

      self.enabled = false
      confine { package_installed?('pe-puppetserver') }
    end
  end

  # Scope which collects PE diagnostics
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for the PE installer
  #     and client tools
  #   - Logs from /var/log/puppetlabs for the PE installer and
  #     PE backup services
  class Scope::Pe < Scope
    def setup(**options)
      confine { package_installed?('pe-puppet-enterprise-release') }
    end

    Scope::Base.add_child(self, name: 'pe')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['client-tools/orchestrator.conf',
                                   'client-tools/puppet-access.conf',
                                   'client-tools/puppet-code.conf',
                                   'client-tools/puppetdb.conf',
                                   'client-tools/services.conf',
                                   'enterprise/conf.d/',
                                   'enterprise/hiera.yaml',
                                   'installer/answers.install'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
    self.add_child(Check::GatherFiles,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['installer/',
                                   'pe-backup-tools/',
                                   'puppet_infra_recover_config_cron.log'],
                            to: 'logs'}])
    self.add_child(Check::PeStatus,
                   name: 'status')
    self.add_child(Check::PeFileSync,
                   name: 'file-sync',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['code-staging'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1},
                           {from: '/opt/puppetlabs/server/data/puppetserver',
                            copy: ['filesync'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
  end

  # Check the status of components related to PE Console Services
  #
  # This check gathers:
  #
  #   - Output from the `status/v1/services` API
  #   - The Directory Service settings, with passwords removed
  class Check::PeConsoleStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')

      data_drop(curl_url('http://127.0.0.1:4432/status/v1/services?level=debug'), ent_directory, 'console_status.json')
      console_ds_settings = curl_cert_auth('https://127.0.0.1:4433/rbac-api/v1/ds')
      data_drop(pretty_json(console_ds_settings, %w[password ds_pw_obfuscated]), ent_directory, 'rbac_directory_settings.json')
    end
  end

  # Check the status of components related to PE Console Services
  #
  # This check gathers:
  #
  #   - A listing of classifier groups configured in the console
  #
  # This check is not enabled by default.
  class Check::PeConsoleGroups < Check
    def setup(**options)
      # Disabled by default as classifier groups configuration can contain
      # sensitive data.
      self.enabled = false
    end

    def run
      ent_directory = File.join(state[:drop_directory], 'enterprise')
      data_drop(curl_cert_auth('https://127.0.0.1:4433/classifier-api/v1/groups'), ent_directory, 'classifier.json')
    end
  end

  # Scope which collects diagnostics related to the PE Console service
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for pe-console-services,
  #     and pe-nginx
  #   - Logs from /var/log/puppetlabs for pe-console-services and pe-nginx
  class Scope::Pe::Console < Scope
    def setup(**options)
      confine { package_installed?('pe-console-services') }
    end

    Scope::Pe.add_child(self, name: 'console')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['console-services/bootstrap.cfg',
                                   'console-services/conf.d/',
                                   'console-services/logback.xml',
                                   'console-services/rbac-certificate-whitelist',
                                   'console-services/request-logging.xml',
                                   'nginx/conf.d/',
                                   'nginx/nginx.conf'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['console-services/',
                                   'nginx/'],
                            to: 'logs'}],
                   services: ['pe-console-services', 'pe-nginx'])
    self.add_child(Check::PeConsoleStatus,
                   name: 'status',
                   services: ['pe-console-services', 'pe-nginx'])
    self.add_child(Check::PeConsoleGroups,
                   name: 'classifier-groups')
  end

  # Check the status of components related to the PE Orchestration service
  #
  # This check gathers:
  #
  #   - Output from the `status/v1/services` API
  class Check::PeOrchestrationStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')

      data_drop(curl_cert_auth('https://127.0.0.1:8143/status/v1/services?level=debug'), ent_directory, 'orchestration_status.json')
    end
  end

  # Scope which collects diagnostics related to the PE Orchestration service
  #
  # This scope gathers:
  #
  #   - Configuration files from /etc/puppetlabs for ace-server, bolt-server,
  #     and pe-orchestration-services
  #   - Logs from /var/log/puppetlabs for ace-server, bolt-server,
  #     and pe-orchestration-services
  #   - Metrics from /opt/puppetlabs/puppet-metrics-collector for
  #     pe-orchestration-services
  class Scope::Pe::Orchestration < Scope
    def setup(**options)
      confine { package_installed?('pe-orchestration-services') }
    end

    Scope::Pe.add_child(self, name: 'orchestration')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/etc/puppetlabs',
                            copy: ['ace-server/conf.d/',
                                   'bolt-server/conf.d/',
                                   'orchestration-services/bootstrap.cfg',
                                   # NOTE: The PE Orchestrator stores encryption keys in its conf.d.
                                   #       Therefore, we explicitly list what to gather.
                                   'orchestration-services/conf.d/analytics.conf',
                                   'orchestration-services/conf.d/auth.conf',
                                   'orchestration-services/conf.d/global.conf',
                                   'orchestration-services/conf.d/inventory.conf',
                                   'orchestration-services/conf.d/metrics.conf',
                                   'orchestration-services/conf.d/orchestrator.conf',
                                   'orchestration-services/conf.d/pcp-broker.conf',
                                   'orchestration-services/conf.d/web-routes.conf',
                                   'orchestration-services/conf.d/webserver.conf',
                                   'orchestration-services/logback.xml',
                                   'orchestration-services/request-logging.xml'],
                            to: 'enterprise/etc/puppetlabs',
                            max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['ace-server/',
                                   'bolt-server/',
                                   'orchestration-services/'],
                            to: 'logs'},
                           # Copy all node activity logs without age limit.
                           {from: '/var/log/puppetlabs',
                            copy: ['orchestration-services/aggregate-node-count*.log*'],
                            to: 'logs',
                            max_age: -1}],
                  services: ['pe-ace-server', 'pe-bolt-server', 'pe-orchestration-services'])
    self.add_child(Check::GatherFiles,
                   name: 'metrics',
                   files: [{from: '/opt/puppetlabs/puppet-metrics-collector',
                            copy: ['orchestrator/'],
                            to: 'metrics'}])
    self.add_child(Check::PeOrchestrationStatus,
                   name: 'status',
                   services: ['pe-ace-server', 'pe-bolt-server', 'pe-orchestration-services'])
  end

  # Check the status of the PE Postgres service
  #
  # This check gathers:
  #
  #   - A list of settings values that the server is using while running
  #   - A list of currently established database connections and the queries
  #     being executed
  #   - A distribution of Puppet run start times for thundering herd detection
  #   - The status of any configured replication slots
  #   - The status of any active replication connections
  #   - The size of database directories on disk
  #   - The size of databases as reported by postgres
  #   - The size of tables and indicies within databases
  class Check::PePostgresqlStatus < Check::ServiceStatus
    def run
      super

      ent_directory = File.join(state[:drop_directory], 'enterprise')
      res_directory = File.join(state[:drop_directory], 'resources')

      data_drop(psql_settings,                ent_directory, 'postgres_settings.txt')
      data_drop(psql_stat_activity,           ent_directory, 'db_stat_activity.txt')
      data_drop(psql_thundering_herd,         ent_directory, 'thundering_herd_query.txt')
      data_drop(psql_replication_slots,       ent_directory, 'postgres_replication_slots.txt')
      data_drop(psql_replication_status,      ent_directory, 'postgres_replication_status.txt')

      exec_drop("ls -d #{PUP_PATHS[:server_data]}/postgresql/*/data #{PUP_PATHS[:server_data]}/postgresql/*/PG_* | xargs du -sh", res_directory, 'db_sizes_from_du.txt')

      psql_data = psql_database_sizes
      data_drop(psql_data, res_directory, 'db_sizes_from_psql.txt')

      databases = psql_databases
      databases = databases.lines.map(&:strip).grep(%r{^pe\-}).sort
      databases.each do |database|
        data_drop(psql_database_relation_sizes(database),          res_directory, 'db_relation_sizes.txt')
        data_drop(psql_database_table_sizes(database),             res_directory, 'db_table_sizes.txt')
        data_drop(psql_total_relation_sizes(database),             res_directory, 'db_total_relation_sizes.txt')
        data_drop(psql_database_relation_sizes_by_table(database), res_directory, 'db_relation_sizes_by_table.txt')
      end
    end

    # Execute psql queries.
    #
    # @param sql [String] SQL to execute via a psql command.
    # @param psql_options [String] list of options to pass to the psql command.
    #
    # @return (see #exec_return_result)

    def psql_return_result(sql, psql_options = '')
      command = %(su pe-postgres --shell /bin/bash --command "true && cd /tmp && #{PUP_PATHS[:server_bin]}/psql #{psql_options} --command \\"#{sql}\\"")
      exec_return_result(command)
    end

    def psql_databases
      sql = %Q(SELECT datname FROM pg_catalog.pg_database;)
      psql_options = '--tuples-only'
      psql_return_result(sql)
    end

    def psql_database_sizes
      sql = %Q(
        SELECT t1.datname AS db_name, pg_size_pretty(pg_database_size(t1.datname))
        FROM pg_database t1
        ORDER BY pg_database_size(t1.datname) DESC;
      )
      psql_return_result(sql)
    end

    # pg_relation_size: Disk space used by the specified fork ('main', 'fsm', 'vm', or 'init' ... defaults to 'main') of the specified table or index.

    def psql_database_relation_sizes(database)
      result = "#{database}\n\n"
      sql = %Q(
        SELECT '#{database}' AS db_name, nspname || '.' || relname AS relation, pg_size_pretty(pg_relation_size(C.oid))
        FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
        WHERE nspname NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
        ORDER BY pg_relation_size(C.oid) DESC;
      )
      psql_options = "--dbname #{database}"
      result << psql_return_result(sql, psql_options)
    end

    # pg_table_size: Disk space used by the specified table, excluding indexes but including TOAST, and all of the forks: 'main', 'fsm', 'vm', 'init'.

    def psql_database_table_sizes(database)
      result = "#{database}\n\n"
      sql = %Q(
        SELECT '#{database}' AS db_name, nspname || '.' || relname AS relation, pg_size_pretty(pg_table_size(C.oid))
        FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
        WHERE nspname NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
        ORDER BY pg_table_size(C.oid) DESC;
      )
      psql_options = "--dbname #{database}"
      result << psql_return_result(sql, psql_options)
    end

    # pg_total_relation_size: Total disk space used by the specified table, including indexes, TOAST, and all of the forks: 'main', 'fsm', 'vm', 'init'.

    def psql_total_relation_sizes(database)
      result = "#{database}\n\n"
      sql = %Q(
        SELECT '#{database}' AS db_name, nspname || '.' || relname AS relation, pg_size_pretty(pg_total_relation_size(C.oid))
        FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
        WHERE nspname NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
        ORDER BY pg_total_relation_size(C.oid) DESC;
      )
      psql_options = "--dbname #{database}"
      result << psql_return_result(sql, psql_options)
    end

    def psql_database_relation_sizes_by_table(database)
      result = "#{database}\n\n"
      sql = %Q(
        WITH
          tables
            AS (
              SELECT
                c.oid, *
              FROM
                pg_catalog.pg_class AS c
                LEFT JOIN pg_catalog.pg_namespace AS n ON
                    n.oid = c.relnamespace
              WHERE
                relkind = 'r'
                AND n.nspname NOT IN ('information_schema', 'pg_catalog')
            ),
          toast
            AS (
              SELECT
                c.oid, *
              FROM
                pg_catalog.pg_class AS c
                LEFT JOIN pg_catalog.pg_namespace AS n ON
                    n.oid = c.relnamespace
              WHERE
                relkind = 't'
                AND n.nspname NOT IN ('information_schema', 'pg_catalog')
            ),
          indices
            AS (
              SELECT
                c.oid, *
              FROM
                pg_catalog.pg_class AS c
                LEFT JOIN pg_catalog.pg_namespace AS n ON
                    n.oid = c.relnamespace
              WHERE
                relkind = 'i'
                AND n.nspname NOT IN ('information_schema', 'pg_catalog')
            )
        SELECT
          '#{database}' || '.' || relname AS name,
          'table' AS type,
          pg_size_pretty(pg_relation_size(oid)) AS size
        FROM
          tables
        UNION
          SELECT
            '#{database}' || '.' || r.relname || '.' || t.relname AS name,
            'toast' AS type,
            pg_size_pretty(pg_relation_size(t.oid)) AS size
          FROM
            toast AS t
            INNER JOIN tables AS r ON t.oid = r.reltoastrelid
        UNION
          SELECT
            '#{database}' || '.' || r.relname || '.' || i.relname AS name,
            'index' AS type,
            pg_size_pretty(pg_relation_size(i.oid)) AS size
          FROM
            indices AS i
            LEFT JOIN pg_catalog.pg_index AS c ON
                i.oid = c.indexrelid
            INNER JOIN tables AS r ON c.indrelid = r.oid
        ORDER BY
          size DESC;
      )
      psql_options = "--dbname #{database}"
      result << psql_return_result(sql, psql_options)
    end

    def psql_settings
      sql = %Q(SELECT * FROM pg_settings;)
      psql_options = '--tuples-only'
      psql_return_result(sql, psql_options)
    end

    def psql_stat_activity
      sql = %Q(SELECT * FROM pg_stat_activity ORDER BY query_start;)
      psql_return_result(sql)
    end

    def psql_replication_slots
      sql = %Q(SELECT * FROM pg_replication_slots;)
      psql_options = '--dbname pe-puppetdb'
      psql_return_result(sql, psql_options)
    end

    def psql_replication_status
      sql = %Q(SELECT * FROM pg_stat_replication;)
      psql_options = '--dbname pe-puppetdb'
      psql_return_result(sql, psql_options)
    end

    def psql_thundering_herd
      sql = %Q(
        SELECT date_part('month', start_time) AS month,
        date_part('day', start_time) AS day,
        date_part('hour', start_time) AS hour,
        date_part('minute', start_time) as minute, count(*)
        FROM reports
        WHERE start_time BETWEEN now() - interval '7 days' AND now()
        GROUP BY date_part('month', start_time), date_part('day', start_time), date_part('hour', start_time), date_part('minute', start_time)
        ORDER BY date_part('month', start_time) DESC, date_part('day', start_time) DESC, date_part( 'hour', start_time ) DESC, date_part('minute', start_time) DESC;
      )
      psql_options = '--dbname pe-puppetdb'
      psql_return_result(sql, psql_options)
    end
  end

  # Scope which collects diagnostics related to the PE Postgres service
  #
  # This scope gathers:
  #
  #   - Configuration files from /opt/puppetlabs/server/data/postgresql
  #     for pe-postgresql
  #   - Logs from /var/log/puppetlabs for pe-postgresql
  #   - Logs from /opt/puppetlabs/server/data/postgresql related to
  #     pe-postgresql upgrades
  class Scope::Pe::Postgres < Scope
    def setup(**options)
      # TODO: Should confine based on whether the pe-postgres package is
      #       installed. But, the package includes a version number and
      #       package_installed? does exact matches only.
      confine { File.executable?("#{PUP_PATHS[:server_bin]}/psql") }
    end

    Scope::Pe.add_child(self, name: 'postgres')

    self.add_child(Check::ConfigFiles,
                   name: 'config',
                   files: [{from: '/opt/puppetlabs/server/data/postgresql',
                            copy: ['*/data/{postgresql.conf,postmaster.opts,pg_ident.conf,pg_hba.conf}'],
                            to: 'enterprise/etc/puppetlabs/postgres',
                            max_age: -1}])
    self.add_child(Check::ServiceLogs,
                   name: 'logs',
                   files: [{from: '/var/log/puppetlabs',
                            copy: ['postgresql/*/'],
                            to: 'logs'},
                           {from: '/opt/puppetlabs/server/data/postgresql',
                            copy: ['pg_upgrade_internal.log',
                                   'pg_upgrade_server.log',
                                   'pg_upgrade_utility.log'],
                            to: 'logs/postgresql'}],
                  services: ['pe-postgresql'])
    self.add_child(Check::PePostgresqlStatus,
                   name: 'status',
                   services: ['pe-postgresql'])
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
    include DiagnosticHelpers

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
      ['puppet', 'facter', 'semantic_puppet/version'].each do |lib|
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

      # NOTE: This is needed because Facter::Core::Execution ends up waiting
      #       in C++ code for subprocesses to complete while holding the Ruby
      #       Global VM Lock (GVL). Thus, any signal handler implemented in
      #       Ruby will be unable to run until the lock is released.
      #       Specifying SYSTEM_DEFAULT uses the libc handlers, which allows
      #       CTRL-C and CTRL-\ to successfuly interrupt a support script that
      #       is waiting for a subcommand to complete (See FACT-2250).
      #
      # TODO: Some of these signal names are not supported on Windows.
      [:INT, :TERM, :QUIT].each do |signal|
        Signal.trap(signal, :SYSTEM_DEFAULT)
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

      begin
        Settings.instance.validate
      rescue => e
        log.error("%{exception_class} raised when validating settings: %{message}\n\t%{backtrace}" %
                  {exception_class: e.class,
                   message: e.message,
                   backtrace: e.backtrace.join("\n\t")})
        return false
      end

      if settings[:encrypt]
        gpg_command = executable?('gpg2') || executable?('gpg')

        if gpg_command.nil?
          log.error('Could not find gpg or gpg2 on the PATH. GPG must be installed to use the --encrypt option')
          return false
        else
          state[:gpg_command] = gpg_command
        end
      end

      if settings[:upload]
        sftp_command = executable?('sftp')

        if sftp_command.nil?
          log.error('Could not find sftp on the PATH. SFTP must be installed to use the --upload option')
          return false
        else
          state[:sftp_command] = sftp_command
        end
      end

      state[:start_time] = DateTime.now

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
        children = @child_specs.map do |(klass, opts)|
          opts ||= {}
          klass.new(**opts)
        end


        if settings[:list]
          children.each(&:describe)

          return state[:exit_code]
        end

        setup_output_directory or return 1
        setup_logfile

        children.each(&:run)

        cleanup_logfile
        output_file = create_output_archive(state[:drop_directory])
        output_file = encrypt_output_archive(output_file) if settings[:encrypt]

        if settings[:upload]
          sftp_upload(output_file)
        else
          display_summary(output_file)
        end
      rescue => e
        log.error("%{exception_class} raised when executing diagnostics: %{message}\n\t%{backtrace}" %
                  {exception_class: e.class,
                   message: e.message,
                   backtrace: e.backtrace.join("\n\t")})

        return 1
      ensure
        cleanup_output_directory
      end

      return state[:exit_code]
    end

    private

    def setup_output_directory
      # Already set up.
      return true if state.key?(:drop_directory)

      parent_dir = File.realdirpath(settings[:dir])
      timestamp = state[:start_time].strftime('%Y%m%d%H%M%S')
      short_hostname = Facter.value('hostname').to_s.split('.').first
      dirname = ['puppet_enterprise_support', settings[:ticket].to_s, short_hostname, timestamp].reject(&:empty?).join('_')

      drop_directory = File.join(parent_dir, dirname)

      display('Creating output directory: %{drop_directory}' %
              {drop_directory: drop_directory})

      return false unless create_path(drop_directory, :mode => 0700)

      # Store drop directory in state to make it available to other methods.
      state[:drop_directory] = drop_directory
      true
    end

    def cleanup_output_directory
      if state.key?(:drop_directory) &&
         File.directory?(state[:drop_directory]) &&
         (! settings[:z_do_not_delete_drop_directory])
        log.info('Cleaning up output directory: %{drop_directory}' %
                 {drop_directory: state[:drop_directory]})

        FileUtils.remove_entry_secure(state[:drop_directory], force: true)
        state.delete(:drop_directory)
      end
    end

    # Create a logfile inside the drop directory
    #
    # A handle to the {::Logger}} created is stored in {Settings#state}
    # under the `:log_file` key.
    #
    # @return [void]
    def setup_logfile
      return if noop? || ! ( state.key?(:drop_directory) &&
                             File.directory?(state[:drop_directory]))

      log_path = File.join(state[:drop_directory], 'support_script_log.jsonl')
      log_file = File.open(log_path, 'w')
      logger = LogManager.file_logger(log_file)

      state[:log_file] = logger
      log.add_logger(logger)
    end

    def cleanup_logfile
      if state.key?(:log_file)
        log.remove_logger(state[:log_file])
        state[:log_file].close
        state.delete(:log_file)
      end
    end

    # Create a tarball from a directory of support script output
    #
    # @param output_directory [String] Path to the support script output
    #   directory.
    #
    # @return [String] Path to the compressed archive.
    def create_output_archive(output_directory)
      tar_change_directory = File.dirname(output_directory)
      tar_directory = File.basename(output_directory)
      output_archive = File.join(settings[:dir], tar_directory + '.tar.gz')

      display('Creating output archive: %{output_archive}' %
              {output_archive: output_archive})

      return output_archive if noop?

      old_umask = File.umask
      begin
        File.umask(0077)
        exec_or_fail(%(tar --create --file - --directory '#{tar_change_directory}' '#{tar_directory}' | gzip --force -9 > '#{output_archive}'))
      ensure
        File.umask(old_umask)
      end

      output_archive
    end

    def encrypt_output_archive(output_archive)
      encrypted_archive = output_archive + '.gpg'
      gpg_homedir = File.join(state[:drop_directory], 'gpg')

      display('Encrypting output archive file: %{output_archive}' %
              {output_archive: output_archive})

      return encrypted_archive if noop?

      FileUtils.mkdir(gpg_homedir, :mode => 0700)
      exec_or_fail(%(echo '#{PGP_KEY}' | '#{state[:gpg_command]}' --quiet --import --homedir '#{gpg_homedir}'))
      exec_or_fail(%(#{state[:gpg_command]} --quiet --homedir "#{gpg_homedir}" --trust-model always --recipient #{PGP_RECIPIENT} --encrypt "#{output_archive}"))
      FileUtils.safe_unlink(output_archive)

      encrypted_archive
    end

    def sftp_upload(output_archive)
      display('Uploading: %{output_archive} via SFTP' %
              {output_archive: output_archive})

      return if noop?

      if settings[:upload_disable_host_key_check]
        ssh_known_hosts = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
      else
        ssh_known_hosts_file = Tempfile.new('csp.ky')
        ssh_known_hosts_file.write(SFTP_KNOWN_HOSTS)
        ssh_known_hosts_file.close
        ssh_known_hosts = "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=#{ssh_known_hosts_file.path}"
      end
      if settings[:upload_user]
        sftp_url = "#{settings[:upload_user]}@#{SFTP_HOST}:/"
      else
        sftp_url = "#{SFTP_USER}@#{SFTP_HOST}:/drop/"
      end
      if settings[:upload_key]
        ssh_key_file = File.absolute_path(settings[:upload_key])
        ssh_identity = "IdentityFile=#{ssh_key_file}"
      else
        ssh_key_file = Tempfile.new('pes.ky')
        ssh_key_file.write(SFTP_KEY)
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
      sftp_command       = %(echo 'put #{output_archive}' | sftp #{ssh_options} #{sftp_url} 2>&1)

      begin
        sftp_output = Facter::Core::Execution.execute(sftp_command)
        if $?.to_i.zero?
          display('File uploaded to: %{sftp_host}' %
                  {sftp_host: SFTP_HOST})
          File.delete(output_archive)
        else
          ssh_key_file.unlink unless settings[:upload_key]
          ssh_known_hosts_file.unlink unless settings[:upload_disable_host_key_check]
          # FIXME: Make i18n friendly
          display ' ** Unable to upload the output archive file. SFTP Output:'
          display
          display sftp_output
          display
          display '    Please manualy upload the output archive file to Puppet Support.'
          display
          display "    Output archive file: #{output_archive}"
          display
        end
      rescue Facter::Core::Execution::ExecutionFailure => e
        ssh_key_file.unlink unless settings[:upload_key]
        ssh_known_hosts_file.unlink unless settings[:upload_disable_host_key_check]
        # FIXME: Make i18n friendly
        display ' ** Unable to upload the output archive file: SFTP command error:'
        display
        display e
        display
        display '    Please manualy upload the output archive file to Puppet Support.'
        display
        display "    Output archive file: #{output_archive}"
        display
      end
    end

    def display_summary(output_archive)
      # FIXME: Make i18n friendly
      display 'Puppet Enterprise customers ...'
      display
      display '  We recommend that you examine the collected data before forwarding to Puppet,'
      display '  as it may contain sensitive information that you may wish to redact.'
      display
      display '  An overview of the data collected by this tool can be found at:'
      display "  #{DOC_URL}"
      display
      display '  Please upload the output archive file to Puppet Support.'
      display
      display "  Output archive file: #{output_archive}"
      display
    end
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

  puts 'Puppet Enterprise Support Script v' + PuppetX::Puppetlabs::SupportScript::VERSION
  puts

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
    opts.separator ''
    opts.separator 'Summary: Collects Puppet Enterprise Support Diagnostics'
    opts.separator ''
    opts.separator 'Options:'
    opts.separator ''
    opts.on('-d', '--dir DIRECTORY', "Output directory. Defaults to: #{default_dir}") do |dir|
      options[:dir] = dir
    end
    opts.on('-e', '--encrypt', 'Encrypt output using GPG') do
      options[:encrypt] = true
    end
    opts.on('-l', '--log_age DAYS', "Log age (in days) to collect. Defaults to: #{default_log_age}") do |log_age|
      options[:log_age] = log_age
    end
    opts.on('-n', '--noop', 'Enable noop mode') do
      options[:noop] = true
    end
    opts.on('--enable LIST', Array, 'Comma-delimited list of scopes or checks to enable') do |list|
      options[:enable] ||= []
      options[:enable] += list
    end
    opts.on('--disable LIST', Array, 'Comma-delimited list of scopes or checks to disable') do |list|
      options[:disable] ||= []
      options[:disable] += list
    end
    opts.on('--only LIST', Array, 'Comma-delimited list of of scopes or checks to run, disabling all others') do |list|
      options[:only] ||= []
      options[:only] += list
    end
    opts.on('--list', 'List available scopes and checks that can be passed to --enable, --disable, or --only.') do |arg|
      options[:list] = true
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
  PuppetX::Puppetlabs::SupportScript::Settings.instance.log.add_logger(PuppetX::Puppetlabs::SupportScript::LogManager.console_logger)
  support = PuppetX::Puppetlabs::SupportScript::Runner.new
  support.add_child(PuppetX::Puppetlabs::SupportScript::Scope::Base, name: '')

  exit support.run
end
