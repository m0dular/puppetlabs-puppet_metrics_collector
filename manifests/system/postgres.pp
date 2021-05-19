# Collect PostgreSQL metrics
#
# This class manages a cron job that uses `/opt/puppetlabs/server/bin/psql`
# to collect metrics from a locally-running `pe-postgresql` service.
#
# This class should not be included directly.
# Include {puppet_metrics_collector::system} instead.
#
# @private
class puppet_metrics_collector::system::postgres (
  String  $metrics_ensure            = $puppet_metrics_collector::system::system_metrics_ensure,
  Integer $collection_frequency      = $puppet_metrics_collector::system::collection_frequency,
  Integer $retention_days            = $puppet_metrics_collector::system::retention_days,
) {
  $metrics_output_dir = "${puppet_metrics_collector::system::output_dir}/postgres"
  $metrics_output_dir_ensure = $metrics_ensure ? {
    'present' => directory,
    'absent'  => absent,
  }
  $service_ensure = $metrics_ensure ? {
    'present' => running,
    'absent'  => stopped,
  }
  $enable_ensure = $metrics_ensure ? {
    'present' => true,
    'absent'  => false,
  }


  file { $metrics_output_dir:
    ensure => $metrics_output_dir_ensure,
    # Allow directories to be removed.
    force  => true,
  }

  $metrics_command = ["${puppet_metrics_collector::system::scripts_dir}/psql_metrics",
                      '--output_dir', $metrics_output_dir,
                      '> /dev/null'].join(' ')

  file { 'postgres_metrics_collection-service':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_postgres-metrics.service',
    content => epp('puppet_metrics_collector/service.epp',
      { 'service' => 'pe_postgres', 'metrics_command' => $metrics_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file { 'postgres_metrics_collection-timer':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_postgres-metrics.timer',
    content => epp('puppet_metrics_collector/timer.epp',
      { 'service' => 'pe_postgres', 'minute' => String($collection_frequency) }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }

  # NOTE - if adding a new service, the name of the service must be added to the valid_paths array in files/metrics_tidy
  $tidy_command = "${puppet_metrics_collector::system::scripts_dir}/metrics_tidy -d ${metrics_output_dir} -r ${retention_days}"
  file { 'pe_postgres-metrics-tidy-service':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_postgres-tidy.service',
    content => epp('puppet_metrics_collector/tidy.epp',
      { 'service' => 'pe_postgres', 'tidy_command' => $tidy_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file { 'pe_postgres-metrics-tidy-timer':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_postgres-tidy.timer',
    content => epp('puppet_metrics_collector/tidy_timer.epp',
      { 'service' => 'pe_postgres' }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { 'pe_postgres-metrics.service':
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { 'pe_postgres-metrics.timer':
    ensure    => $service_ensure,
    enable    => $enable_ensure,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File['/etc/systemd/system/pe_postgres-metrics.timer'],
  }

  service { 'pe_postgres-tidy.service':
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { 'pe_postgres-tidy.timer':
    ensure    => $service_ensure,
    enable    => $enable_ensure,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File['/etc/systemd/system/pe_postgres-tidy.timer'],
  }


  # Legacy cleanup
  ['postgres_metrics_tidy', 'postgres_metrics_collection'].each |$cron| {
    cron { $cron:
      ensure => absent,
    }
  }
}
