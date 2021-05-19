# Collect VMware metrics
#
# This class manages a cron job that collects metrics from:
#
#     vmware-toolbox-cmd stat
#
# This class should not be included directly.
# Include {puppet_metrics_collector::system} instead.
#
# @private
class puppet_metrics_collector::system::vmware (
  String  $metrics_ensure            = $puppet_metrics_collector::system::system_metrics_ensure,
  Integer $collection_frequency      = $puppet_metrics_collector::system::collection_frequency,
  Integer $retention_days            = $puppet_metrics_collector::system::retention_days,
) {
  $metrics_output_dir = "${puppet_metrics_collector::system::output_dir}/vmware"
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

  $metrics_command = ["${puppet_metrics_collector::system::scripts_dir}/vmware_metrics",
                      '--output_dir', $metrics_output_dir,
                      '> /dev/null'].join(' ')

  if ($metrics_ensure == 'present') and (!$facts.dig('puppet_metrics_collector', 'have_vmware_tools')) {
    notify { 'vmware_tools_warning':
      message  => 'VMware metrics collection requires vmware-toolbox-cmd to be on the PATH',
      loglevel => warning,
    }
  }

  file { 'pe_vmware-metrics-service':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_vmware-metrics.service',
    content => epp('puppet_metrics_collector/service.epp',
      { 'service' => 'pe_vmware', 'metrics_command' => $metrics_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file { 'pe_vmware-metrics-timer':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_vmware-metrics.timer',
    content => epp('puppet_metrics_collector/timer.epp',
      { 'service' => 'pe_vmware', 'minute' => String($collection_frequency) }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }

  # NOTE - if adding a new service, the name of the service must be added to the valid_paths array in files/metrics_tidy
  $tidy_command = "${puppet_metrics_collector::system::scripts_dir}/metrics_tidy -d ${metrics_output_dir} -r ${retention_days}"
  file { 'pe_vmware-metrics-tidy-service':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_vmware-tidy.service',
    content => epp('puppet_metrics_collector/tidy.epp',
      { 'service' => 'pe_vmware', 'tidy_command' => $tidy_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file { 'pe_vmware-metrics-tidy-timer':
    ensure  => $metrics_ensure,
    path    => '/etc/systemd/system/pe_vmware-tidy.timer',
    content => epp('puppet_metrics_collector/tidy_timer.epp',
      { 'service' => 'pe_vmware' }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }

  service { 'pe_vmware-metrics.service':
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { 'pe_vmware-metrics.timer':
    ensure    => $service_ensure,
    enable    => $enable_ensure,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File['/etc/systemd/system/pe_vmware-metrics.timer'],
  }

  service { 'pe_vmware-tidy.service':
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { 'pe_vmware-tidy.timer':
    ensure    => $service_ensure,
    enable    => $enable_ensure,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File['/etc/systemd/system/pe_vmware-tidy.timer'],
  }


  # Legacy cleanup
  ['vmware_metrics_tidy', 'vmware_metrics_collection'].each |$cron| {
    cron { $cron:
      ensure => absent,
    }
  }
}
