#!/opt/puppetlabs/puppet/bin/ruby

require 'json'

module PuppetX
  module Puppetlabs
    # Collects diagnostic information about Puppet Enterprise for Support.
    class Support
      def initialize(options)
        @version = '2.0.0'
        @doc_url = 'https://puppet.com/docs/pe/2018.1/getting_support_for_pe.html#the-pe-support-script'

        @paths = {
          puppetlabs_bin: '/opt/puppetlabs/bin',
          puppet_bin:     '/opt/puppetlabs/puppet/bin',
          server_bin:     '/opt/puppetlabs/server/bin',
          server_data:    '/opt/puppetlabs/server/data',
        }

        @options = options
        @options[:version] = @version
        @options[:log_age] = (@options[:log_age].to_s == 'all') ? 999 : @options[:log_age].to_i
        @options[:scope]   = Hash[@options[:scope].split(',').product([true])]

        @pgp_recipient  = 'FD172197'
        @pgp_public_key = pgppublickey

        @platform = {}
        @packages = {}
        @users = {}
        @saves = {}

        inspect_user
        inspect_platform
        inspect_output_directory

        @drop_directory = create_drop_directory
        verify_drop_directory_disk_space

        @log_file = "#{@drop_directory}/log.txt"

        data_drop(JSON.pretty_generate(@options), @drop_directory, 'metadata.json')

        collect_scope_enterprise if @options[:scope]['enterprise']
        collect_scope_etc        if @options[:scope]['etc']
        collect_scope_log        if @options[:scope]['log']
        collect_scope_networking if @options[:scope]['networking']
        collect_scope_resources  if @options[:scope]['resources']
        collect_scope_system     if @options[:scope]['system']

        @output_archive = create_output_archive
        report_output_archive
      end

      #=========================================================================
      # Puppet Enterprise Services and Paths
      #=========================================================================

      # Puppet Enterprise Services

      def puppet_enterprise_services_list
        [
          'pe-activemq',
          'pe-console-services',
          'pe-nginx',
          'pe-orchestration-services',
          'pe-puppetdb',
          'pe-puppetserver',
          'pe-razor-server',
          'puppet',
          'pxp-agent',
        ]
      end

      # Puppet Enterprise Directories

      def puppet_enterprise_directories_list
        [
          '/etc/puppetlabs',
          '/opt/puppetlabs',
          '/var/lib/peadmin',
          '/var/log/puppetlabs',
        ]
      end

      # Puppet Enterprise Configuration Files and Directories

      def puppet_enterprise_config_list
        files = [
          'activemq/activemq.xml',
          'activemq/jetty.xml',
          'activemq/log4j.properties',
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
          'orchestration-services/conf.d',
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
          'r10k/r10k.yaml',
        ]
        files.map { |file| "/etc/puppetlabs/#{file}" }
      end

      # Puppet Enterprise Configuration Files to Redact

      def puppet_enterprise_config_list_to_redact
        files = [
          'activemq/activemq.xml',
          'peadmin_mcollective_client.cfg',
          'mcollective/server.cfg',
          '*/conf.d/*',
        ]
        files.map { |file| "/etc/puppetlabs/#{file}" }
      end

      # System Config Files

      def system_config_list
        files = [
          'apt/apt.conf.d',
          'apt/sources.list.d',
          'hosts',
          'nsswitch.conf',
          'resolv.conf',
          'yum.conf',
          'yum.repos.d',
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
          'pg_hba.conf',
        ]
        files.map { |file| "#{@paths[:server_data]}/postgresql/9.6/data/#{file}" }
      end

      # Puppet Enterprise PostgreSQL Upgrade Log Files
      # Instance Variables: @paths

      def puppet_enterprise_database_upgrade_log_list
        files = [
          'pg_upgrade_internal.log',
          'pg_upgrade_server.log',
          'pg_upgrade_utility.log',
        ]
        files.map { |file| "#{@paths[:server_data]}/postgresql/#{file}" }
      end

      #=========================================================================
      # Scopes
      #=========================================================================

      # Collect Puppet Enterprise diagnostics.
      # Instance Variables: @drop_directory, @options, @paths, @platform

      def collect_scope_enterprise
        display 'Collecting Enterprise Diagnostics'
        display

        scope_directory = "#{@drop_directory}/enterprise"

        # Collect Puppet Enterprise packages.
        pe_packages = package_listing('^pe-|^puppet')
        data_drop(pe_packages, scope_directory, 'puppet_packages.txt')

        # Collect list of Puppet Enterprise files.
        pe_directories = puppet_enterprise_directories_list
        pe_directories += conf_puppet_master_basemodulepath.split(':')
        pe_directories += conf_puppet_master_environmentpath.split(':')
        pe_directories += conf_puppet_master_modulepath.split(':')
        pe_directories.uniq.sort.each do |directory|
          directory_file_name = directory.tr('/', '_')
          exec_drop("ls -alR #{directory}", scope_directory, "list_#{directory_file_name}.txt".squeeze('_'))
        end

        # Collect Puppet certs.
        exec_drop("#{@paths[:puppet_bin]}/puppet cert list --all", scope_directory, 'puppet_cert_list.txt')

        # Collect Puppet config.
        exec_drop("#{@paths[:puppet_bin]}/puppet config print --color=false",         scope_directory, 'puppet_config_print.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet config print --color=false --debug", scope_directory, 'puppet_config_print_debug.txt')

        # Collect Puppet facts.
        exec_drop("#{@paths[:puppet_bin]}/puppet facts --color=false",         scope_directory, 'puppet_facts.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet facts --color=false --debug", scope_directory, 'puppet_facts_debug.txt')

        # Collect Puppet and Puppetserver gems.
        exec_drop("#{@paths[:puppet_bin]}/gem --list --local",                  scope_directory, 'puppet_gem_list.txt')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppetserver gem --list --local", scope_directory, 'puppetserver_gem_list.txt')

        # Collect Puppet modules.
        exec_drop("#{@paths[:puppet_bin]}/puppet module list --color=false",    scope_directory, 'puppet_modules_list.txt')
        exec_drop("#{@paths[:puppet_bin]}/puppet module list --render-as yaml", scope_directory, 'puppet_modules_list.yaml')

        # Collect Puppet Enterprise module changes.
        pe_module_path = '/opt/puppetlabs/puppet/modules'
        Dir.foreach(pe_module_path) do |file|
          next if ['.', '..'].include?(file)
          pe_module = "#{pe_module_path}/#{file}"
          next unless File.directory?(pe_module)
          data_drop("#{pe_module}:", scope_directory, 'puppet_enterprise_module_changes.txt')
          exec_drop("#{@paths[:puppet_bin]}/puppet module changes #{pe_module} --render-as yaml", scope_directory, 'puppet_enterprise_module_changes.txt')
        end

        # Collect Puppet Enterprise Environment diagnostics.
        environments_json = curl_puppetserver_environments
        environments = JSON.parse(environments_json)
        environments['environments'].keys.each do |environment|
          environment_manifests = environments['environments'][environment]['settings']['manifest']
          environment_directory = File.dirname(environment_manifests)
          environment_modules_drop_directory = "#{scope_directory}/environments/#{environment}/modules"
          exec_drop("#{@paths[:puppet_bin]}/puppet module list --color=false --environment=#{environment}",    environment_modules_drop_directory, 'puppet_modules_list.txt')
          exec_drop("#{@paths[:puppet_bin]}/puppet module list --render-as yaml --environment=#{environment}", environment_modules_drop_directory, 'puppet_modules_list.yaml')
          # Scope Redirect: This drops into etc instead of enterprise.
          copy_drop("#{environment_directory}/environment.conf", @drop_directory)
          copy_drop("#{environment_directory}/hiera.yaml",       @drop_directory)
          copy_drop("#{environment_manifests}/site.pp",          @drop_directory)
        end

        # Collect Puppet Enterprise Classifier groups.
        if @options[:classifier]
          data_drop(curl_classifier_groups, scope_directory, 'classifier_groups.json')
        end

        # Collect Puppet Enterprise Service diagnostics.
        data_drop(curl_console_status,          scope_directory, 'console_status.json')
        data_drop(curl_orchestrator_status,     scope_directory, 'orchestrator_status.json')
        data_drop(curl_puppetdb_status,         scope_directory, 'puppetdb_status.json')
        data_drop(curl_puppetdb_summary_stats,  scope_directory, 'puppetdb_summary_stats.json')
        data_drop(environments_json,            scope_directory, 'puppetserver_environments.json')
        data_drop(curl_puppetserver_status,     scope_directory, 'puppetserver_status.json')

        # Collect Puppet Enterprise Database diagnostics.
        data_drop(psql_settings,                scope_directory, 'postgres_settings.txt')
        data_drop(psql_stat_activity,           scope_directory, 'postgres_stat_activity.txt')
        data_drop(psql_rbac_directory_settings, scope_directory, 'rbac_directory_settings.txt')
        data_drop(psql_thundering_herd,         scope_directory, 'thundering_herd.txt')

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

        # Collect Puppet Enterprise ActiveMQ diagnostics.
        data_drop('File descriptors in use by pe-activemq:', scope_directory, 'activemq_resource_limits.txt')
        exec_drop('lsof -u pe-activemq | wc -l',             scope_directory, 'activemq_resource_limits.txt')
        data_drop('Resource limits for pe-activemq:',        scope_directory, 'activemq_resource_limits.txt')
        exec_drop('ulimit -a',                               scope_directory, 'activemq_resource_limits.txt', 'pe-activemq')

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
        filesync_directory = "#{@paths[:server_data]}/puppetserver/filesync"
        exec_drop("du -h --max-depth=1 #{code_staging_directory}", scope_directory, 'code_staging_sizes_from_du.txt') if File.directory?(code_staging_directory)
        exec_drop("du -h --max-depth=1 #{filesync_directory}",     scope_directory, 'filesync_sizes_from_du.txt')     if File.directory?(filesync_directory)
        if @options[:filesync]
          # Scope Redirect: This drops into etc instead of enterprise.
          copy_drop(code_staging_directory, @drop_directory)
          # Scope Redirect: This drops into opt instead of enterprise.
          copy_drop(filesync_directory, @drop_directory)
        end

        # Collect Puppet Enterprise Infrastructure diagnostics.
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure status --format json",                 scope_directory, 'puppet_infra_status.json')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure tune --color=false --debug",           scope_directory, 'puppet_infra_tune.txt')
        exec_drop("#{@paths[:puppetlabs_bin]}/puppet-infrastructure tune --color=false --debug --current", scope_directory, 'puppet_infra_tune_current.txt')

        # Collect Puppet Enterprise Metrics.
        recreate_parent_path = false
        copy_drop('/opt/puppetlabs/pe_metric_curl_cron_jobs', scope_directory, recreate_parent_path)
        copy_drop('/opt/puppetlabs/puppet-metrics-collector', scope_directory, recreate_parent_path)
      end

      # Collect system configuration files.
      # Instance Variables: @drop_directory, @options

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
        # Note: This does not fit into an existing *_drop method.
        unless noop?
          puppet_enterprise_config_list_to_redact.each do |file|
            command = %(ls -1 #{@drop_directory}/#{file} 2>/dev/null | xargs --no-run-if-empty sed --in-place '/password/d')
            exec_return_status(command)
          end
        end

        sos_clean("#{@drop_directory}/etc/hosts", "#{@drop_directory}/hosts")
      end

      # Collect puppet and system logs.
      # Instance Variables: @drop_directory, @options, @paths

      def collect_scope_log
        display 'Collecting Log Files'
        display

        scope_directory = "#{@drop_directory}/var/log"

        copy_drop('/var/log/messages',     @drop_directory)
        copy_drop('/var/log/syslog',       @drop_directory)
        copy_drop('/var/log/system',       @drop_directory)
        exec_drop('dmesg',                 scope_directory, 'dmesg.txt')

        copy_drop('/var/log/puppetlabs/installer', @drop_directory)

        # Copy log files based upon age.
        # Note: This does not fit into an existing *_drop method.
        unless noop?
          command = %(find /var/log/puppetlabs -type f -mtime -#{@options[:log_age]} | xargs --no-run-if-empty cp --parents --preserve --target-directory #{@drop_directory})
          exec_return_status(command)
        end

        puppet_enterprise_services_list.each do |service|
          exec_drop("journalctl --full --output=short-iso --unit=#{service} --since '#{@options[:log_age]} days ago'", scope_directory, "#{service}-journalctl.log")
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
        return false unless exec_return_status(%(mkdir --parents "#{dst}"))
        exec_return_status(command_line, timeout)
      end

      # Append data to a file in the destination directory.

      def data_drop(data, dst, file)
        file_name = "#{dst}/#{file}"
        logline "data_drop: #{dst} to #{file}"
        if @saves.key?(file_name)
          @saves[file_name] = @saves[file_name] + 1
          display " ** Append: #{file} # #{@saves[file_name]}"
        else
          display " ** Saving: #{file}"
          @saves[file_name] = 1
        end
        display
        return if noop?
        return false unless exec_return_status(%(mkdir --parents "#{dst}"))
        # data = 'This file is empty.' if data == ''
        File.open(file_name, 'a') { |f| f.puts(data) }
      end

      # Copy directories or files to the destination directory, recreating the parent path by default.
      #
      # Rather than testing for the existance of the source in the calling scope,
      # test for the existance of the source in the method.

      def copy_drop(src, dst, recreate_parent_path = true)
        parents_option = recreate_parent_path ? ' --parents ' : ''
        recursive_option = File.directory?(src) ? ' --recursive ' : ''
        command_line = %(cp --dereference --preserve #{parents_option}#{recursive_option} "#{src}" "#{dst}")
        unless File.exist?(src)
          logline "copy_drop: source not found: #{src}"
          return false
        end
        logline "copy_drop: #{command_line}"
        display " ** Saving: #{src}"
        display
        return if noop?
        return false unless exec_return_status(%(mkdir --parents "#{dst}"))
        exec_return_status(command_line)
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

      # Inspect the runtime user.

      def inspect_user
        script_name = File.basename(__FILE__)
        command = %(id --user)
        result = exec_return_result(command)
        fail_and_exit("#{script_name} must be run as root") unless result == '0'
        true
      end

      # Inspects the runtime platform.
      # Instance Variables: @platform
      #
      # name      : Name of the platorm, e.g. "centos".
      # release   : Release version, e.g. "10.10".
      # hostname  : Hostname of this machine, e.g. "host".
      # fqdn      : Fully qualified hostname of this machine, e.g. "host.example.com".
      # packaging : Name of packaging system, e.g. "rpm".

      def inspect_platform
        os = Facter.value('os')
        @platform[:name]     = os['name'].downcase
        @platform[:release]  = os['release']['major'] + os['release']['minor']
        @platform[:hostname] = Facter.value('hostname').downcase
        @platform[:fqdn]     = Facter.value('fqdn').downcase
        case @platform[:name]
        when 'amazon', 'aix', 'centos', 'eos', 'fedora', 'rhel', 'sles'
          @platform[:packaging] = 'rpm'
        when 'debian', 'cumulus', 'ubuntu'
          @platform[:packaging] = 'dpkg'
        else
          @platform[:packaging] = ''
          logline "inspect_platform: unknown packaging system for platform: #{@platform[:name]}"
          display_warning("Unknown packaging system for platform: #{@platform[:name]}")
        end
        true
      end

      # Inspect the drop directory.
      # Instance Variables: @options

      def inspect_output_directory
        fail_and_exit("Output directory #{@options[:dir]} does not exist") unless File.directory?(@options[:dir])
        fail_and_exit("Output directory #{@options[:dir]} cannot be a symlink") if File.symlink?(@options[:dir])
        true
      end

      # Collect all packages that are part of the Puppet Enterprise installation
      # Instance Variables: @platform

      def package_listing(regex)
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
          logline "package_listing: unable to list packages for platform: #{@platform[:name]}"
          display_warning("Unable to list packages for platform: #{@platform[:name]}")
        end
        result
      end

      # Query a package and cache the results.
      # Instance Variables: @packages, @platform

      def package_installed?(package)
        result = false
        return @packages[package] if @packages.key?(package)
        case @platform[:packaging]
        when 'rpm'
          result = exec_return_result(%(rpm --query --info #{package})) =~ %r{Version}
        when 'dpkg'
          result = exec_return_result(%(dpkg-query  --show #{package})) =~ %r{Version}
        else
          logline "package_installed: unable to query package for platform: #{@platform[:name]}"
          display_warning("Unable to query package for platform: #{@platform[:name]}")
        end
        @packages[package] = result
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

      # Puppet[:master]

      def conf_puppet_agent_server
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent server))
        result = 'puppet' if result == ''
        result
      end

      # Puppet[:hostcert]

      def conf_puppet_agent_hostcert
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent hostcert))
        result = exec_return_result(%(/etc/puppetlabs/puppet/ssl/certs/$(hostname -f).pem)) if result == ''
        result
      end

      # Puppet[:hostprivkey]

      def conf_puppet_agent_hostprivkey
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section agent hostprivkey))
        result = exec_return_result(%(/etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f).pem)) if result == ''
        result
      end

      def conf_puppet_master_basemodulepath
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master basemodulepath))
        result = '/etc/puppetlabs/code/modules:/opt/puppetlabs/puppet/modules' if result == ''
        result
      end

      def conf_puppet_master_environmentpath
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master environmentpath))
        result = '/etc/puppetlabs/code/environments' if result == ''
        result
      end

      def conf_puppet_master_modulepath
        result = exec_return_result(%(#{@paths[:puppet_bin]}/puppet config print --section master modulepath))
        result = '/etc/puppetlabs/code/environments/production/modules:/etc/puppetlabs/code/modules:/opt/puppetlabs/puppet/modules' if result == ''
        result
      end

      #=========================================================================
      # Query Puppet Enterprise API
      #=========================================================================

      # Common curl parameters.

      def curl_auth
        "--cert #{conf_puppet_agent_hostcert} --key #{conf_puppet_agent_hostprivkey}"
      end

      def curl_opts
        '--silent --show-error --connect-timeout 5 --max-time 60'
      end

      # Port 8080 is often used by other services.

      def puppetdb_port
        result = exec_return_result(%(cat /etc/puppetlabs/puppetdb/conf.d/jetty.ini | sed 's/ //g' | grep --extended-regexp '^port=[[:digit:]]+$'))
        return 8080 if result == ''
        result.split('=')[1]
      end

      # Execute a curl command and return the results.
      # Instance Variables: @paths

      def curl_console_status
        return '' unless package_installed?('pe-console-services')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} http://127.0.0.1:4432/status/v1/services?level=debug))
        pretty_json(result)
      end

      def curl_orchestrator_status
        return '' unless package_installed?('pe-orchestration-services')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} --insecure https://127.0.0.1:8143/status/v1/services?level=debug))
        pretty_json(result)
      end

      def curl_puppetserver_status
        return '' unless package_installed?('pe-puppetserver')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} --insecure https://127.0.0.1:8140/status/v1/services?level=debug))
        pretty_json(result)
      end

      def curl_puppetdb_status
        return '' unless package_installed?('pe-puppetdb')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} -X GET http://127.0.0.1:#{puppetdb_port}/status/v1/services?level=debug))
        pretty_json(result)
      end

      def curl_classifier_groups
        return '' unless package_installed?('pe-console-services')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure https://127.0.0.1:4433/classifier-api/v1/groups))
        pretty_json(result)
      end

      def curl_puppetdb_summary_stats
        return '' unless package_installed?('pe-puppetdb')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} -X GET http://127.0.0.1:8080/pdb/admin/v1/summary-stats))
        pretty_json(result)
      end

      def curl_puppetserver_environments
        return '' unless package_installed?('pe-puppetserver')
        result = exec_return_result(%(#{@paths[:puppet_bin]}/curl #{curl_opts} #{curl_auth} --insecure https://127.0.0.1:8140/puppet/v3/environments))
        pretty_json(result)
      end

      #=========================================================================
      # Query Puppet PostgreSQL
      #=========================================================================

      # Execute a psql command using the pe-postgres and return the results or an empty string.
      # Instance Variables: @paths

      def psql_databases
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT datname FROM pg_catalog.pg_database;'
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --tuples-only --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_database_sizes
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT t1.datname AS db_name, pg_size_pretty(pg_database_size(t1.datname)) FROM pg_database t1 ORDER BY pg_database_size(t1.datname) DESC;'
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_database_relation_sizes(database)
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        result = "#{database}\n\n"
        sql = "SELECT '#{database}' AS db_name, nspname || '.' || relname AS relation, pg_size_pretty(pg_relation_size(C.oid)) \
          FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace) WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') \
          ORDER BY pg_relation_size(C.oid) DESC;"
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname #{database} --command \\"#{sql}\\"")
        result << exec_return_result(command)
      end

      def psql_settings
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_settings;'
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --tuples-only --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_stat_activity
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT * FROM pg_stat_activity ORDER BY query_start;'
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --command '#{sql}'")
        exec_return_result(command)
      end

      def psql_rbac_directory_settings
        return '' unless package_installed?('pe-puppetdb') && user_exists?('pe-postgres')
        sql = 'SELECT row_to_json(row) \
          FROM ( \
          SELECT id, display_name, help_link, type, hostname, port, ssl, login, connect_timeout, base_dn, user_rdn, user_display_name_attr, user_email_attr, user_lookup_attr, \
          group_rdn, group_object_class, group_name_attr, group_member_attr, group_lookup_attr FROM directory_settings \
          ) row;'
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname pe-rbac --command '#{sql}'")
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
        command = %(su - pe-postgres --shell /bin/bash --command "#{@paths[:server_bin]}/psql --dbname pe-puppetdb --command \\"#{sql}\\"")
        exec_return_result(command)
      end

      #=========================================================================
      # Manage Output Directory and Output Archive
      #=========================================================================

      # Avoid interacting with system directories.

      def unsupported_drop_directory?(directory)
        return true if directory.nil?
        return true if directory == ''
        absolute_path = File.realdirpath(directory)
        return true if ['/', '/boot', '/dev', '/proc', '/run', '/sys'].include?(absolute_path)
        false
      end

      # Create the drop directory or exit.
      # Instance Variables: @drop_directory, @options, @platform

      def create_drop_directory
        timestamp = Time.now.strftime('%Y-%m-%d_%s')
        drop_directory = ["#{@options[:dir]}/puppet_enterprise_support", @options[:ticket], @platform[:hostname], timestamp].reject(&:empty?).join('_')
        if unsupported_drop_directory?(drop_directory)
          fail_and_exit("Unable to create unsupported output directory: #{drop_directory}")
        end
        display "Creating output directory: #{drop_directory}"
        display
        exec_or_fail(%(rm -rf "#{drop_directory}"))
        exec_or_fail(%(mkdir -p "#{drop_directory}"))
        exec_or_fail(%(chmod 700 "#{drop_directory}"))
        drop_directory
      end

      # Verify necessary disk space or exit.
      # Instance Variables: @drop_directory, @options

      def verify_drop_directory_disk_space
        available = 0
        # Minimum: 32MB plus sources.
        required = 32_768
        directories = [
          '/var/log/puppetlabs',
          '/opt/puppetlabs/pe_metric_curl_cron_jobs',
          '/opt/puppetlabs/puppet-metrics-collector',
        ]
        if @options[:filesync]
          directories.push('/etc/puppetlabs/code-staging')
          directories.push("#{@paths[:server_data]}/puppetserver/filesync")
        end
        directories.each do |directory|
          if File.directory?(directory)
            result = exec_return_result(%(du -sk #{directory}))
            required += result.split(' ')[0].to_i unless result == ''
          end
        end
        # Double the total used by source directories, since copy before archive and compress.
        required = (required * 2) / 1024
        result = exec_return_result(%(df -Pk "#{@drop_directory}" | grep -v Available))
        available = result.split(' ')[3].to_i / 1024 unless result == ''
        unless available > required
          exec_return_status(%(rm -rf "#{@drop_directory}"))
          fail_and_exit("Not enough disk space for #{@drop_directory}. Available: #{available} MB, Required: #{required} MB")
        end
        required
      end

      # Archive, compress, and optionally encrypt the drop directory or exit.
      # Instance Variables: @drop_directory, @options, @pgp_public_key, @pgp_recipient

      def create_output_archive
        display "Processing output directory: #{@drop_directory}"
        display
        display " ** Archiving output directory: #{@drop_directory}"
        display
        tar_change_directory = File.dirname(@drop_directory)
        tar_directory = File.basename(@drop_directory)
        output_archive = "#{@drop_directory}.tar.gz"
        exec_or_fail(%(umask 0077 && tar --create --file - --directory "#{tar_change_directory}" "#{tar_directory}" | gzip --force -9 > "#{output_archive}"))
        delete_drop_directory
        if @options[:encrypt]
          gpg_command = executable?('gpg') ? 'gpg' : nil
          gpg_command = 'gpg2' if executable?('gpg2')
          unless gpg_command
            fail_and_exit('Could not find gpg or gpg2 on the PATH. GPG must be installed to use the --encrypt option')
          end
          display " ** Encrypting output archive file: #{output_archive}"
          display
          exec_or_fail(%(mkdir "#{@drop_directory}/gpg"))
          exec_or_fail(%(chmod 600 "#{@drop_directory}/gpg"))
          exec_or_fail(%(echo "#{@pgp_public_key}" | "#{gpg_command}" --quiet --import --homedir "#{@drop_directory}/gpg"))
          exec_or_fail(%(#{gpg_command} --quiet --homedir "#{@drop_directory}/gpg" --trust-model always --recipient #{@pgp_recipient} --encrypt "#{output_archive}"))
          exec_or_fail(%(rm -f "#{output_archive}"))
          output_archive = "#{output_archive}.gpg"
        end
        output_archive
      end

      # Delete the drop directory or exit.
      # Instance Variables: @drop_directory, @options

      def delete_drop_directory
        return if @options[:z_do_not_delete_drop_directory]
        if unsupported_drop_directory?(@drop_directory)
          fail_and_exit("Unable to delete unsupported output directory: #{@drop_directory}")
        end
        display "Deleting output directory: #{@drop_directory}"
        display
        exec_or_fail(%(rm -rf "#{@drop_directory}"))
      end

      # Summary.
      # Instance Variables: @doc_url, @output_archive

      def report_output_archive
        display 'Done!'
        display
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
        display "Output archive file: #{@output_archive}"
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
        File.open(@log_file, 'a') { |f| f.puts(datum) }
      end

      # Execute a command line and return the result or an empty string.
      # Used by methods that collect diagnostics.

      def exec_return_result(command_line, timeout = 0)
        options = { timeout: timeout }
        Facter::Core::Execution.execute(command_line, options)
      rescue Facter::Core::Execution::ExecutionFailure
        logline "error: exec_return_result: command failed: #{command_line}"
        display "    Command failed: #{command_line}"
        display
        ''
      end

      # Execute a command line and return true or false.

      def exec_return_status(command_line, timeout = 0)
        options = { timeout: timeout }
        Facter::Core::Execution.execute(command_line, options)
        $?.to_i.zero?
      rescue Facter::Core::Execution::ExecutionFailure
        logline "error: exec_return_status: command failed: #{command_line}"
        display "    Command failed: #{command_line}"
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
      rescue Facter::Core::Execution::ExecutionFailure
        logline "error: exec_or_fail: command failed: #{command_line}"
        fail_and_exit("Command failed: #{command_line}")
      end

      # Test for command existance.

      def executable?(command)
        Facter::Core::Execution.which(command)
      end

      # Test for noop mode.
      # Instance Variables: @options

      def noop?
        @options[:noop] == true
      end

      # Reformat JSON Pretty.

      def pretty_json(datum)
        return datum if datum == ''
        JSON.pretty_generate(JSON.parse(datum))
      end

      #=========================================================================
      # Data
      #=========================================================================

      def pgppublickey
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
    end
  end
end

# The following allows this class to be executed as a standalone script.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'optparse'

  version = '2.0.0'

  # See also: lib/puppet/face/enterprise/support.rb
  default_dir     = File.directory?('/var/tmp') ? '/var/tmp' : '/tmp'
  default_log_age = 14
  default_scope   = %w[enterprise etc log networking resources system].join(',')

  puts "Puppet Enterprise Support Script Version #{version}"
  puts

  begin
    require 'facter'
  rescue LoadError
    puts "Error: 'facter' gem is not installed."
    exit 1
  end

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
    opts.separator ''
    opts.separator 'Summary: Collects Puppet Enterprise Support Diagnostics'
    opts.separator ''
    opts.separator 'Options:'
    opts.separator ''
    options[:classifier] = false
    opts.on('-c', '--classifier', 'Include Classifier data') do
      options[:classifier] = true
    end
    options[:dir] = default_dir
    opts.on('-d', '--dir DIRECTORY', "Output directory. Defaults to: #{default_dir}") do |dir|
      options[:dir] = dir
    end
    options[:encrypt] = false
    opts.on('-e', '--encrypt', 'Encrypt output using GPG') do
      options[:encrypt] = true
    end
    options[:filesync] = false
    opts.on('-f', '--filesync', 'Include FileSync data') do
      options[:filesync] = true
    end
    options[:log_age] = default_log_age
    opts.on('-l', '--log_age DAYS', "Log age (in days) to collect. Defaults to: #{default_log_age}") do |log_age|
      unless log_age =~ %r{^\d+|all$}
        puts "Error: The log-age parameter must be a number, or the string 'all'. Got: #{log_age}"
        exit 1
      end
      @options[:log_age] = log_age
    end
    options[:noop] = false
    opts.on('-n', '--noop', 'Enable noop mode') do
      options[:noop] = true
    end
    options[:scope] = default_scope
    opts.on('-s', '--scope LIST', "Scope (comma-delimited) of diagnostics to collect. Defaults to: #{default_scope}") do |scope|
      options_scope = scope.tr(' ', '')
      unless options_scope =~ %r{^(\w+)(,\w+)*$}
        puts "Error: The scope parameter must be a comma-delimited list. Got: #{scope}"
        exit 1
      end
      options[:scope] = options_scope
    end
    options[:ticket] = ''
    opts.on('-t', '--ticket NUMBER', 'Support ticket number') do |ticket|
      unless ticket =~ %r{^all|\d+$}
        puts "Error: The ticket parameter may contain only numbers, letters, and dashes. Got: #{ticket}"
        exit 1
      end
      options[:ticket] = ticket
    end
    options[:z_do_not_delete_drop_directory] = false
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

  Support = PuppetX::Puppetlabs::Support.new(options)
end
