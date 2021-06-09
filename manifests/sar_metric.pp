# Collect System Metrics
define puppet_metrics_collector::sar_metric (
  String                    $metrics_type              = $title,
  Enum['absent', 'present'] $metric_ensure             = 'present',
  String                    $cron_minute               = '0/5',
  Integer                   $retention_days            = 90,
  Integer                   $collection_frequency      = 5, # minutes
  Integer                   $polling_frequency_seconds = 1,
  String                    $metric_script_file        = 'system_metrics',
) {

  $metrics_output_dir = "${puppet_metrics_collector::system::output_dir}/${metrics_type}"

  $metrics_output_dir_ensure = $metric_ensure ? {
    'present' => directory,
    'absent'  => absent,
  }
  $service_ensure = $metric_ensure ? {
    'present' => running,
    'absent'  => stopped,
  }

  $service_enable = $metric_ensure ? {
    'present' => true,
    'absent'  => false,
  }

  file { $metrics_output_dir :
    ensure => $metrics_output_dir_ensure,
    # Allow directories to be removed.
    force  => true,
  }

  $metric_script_file_path = "${puppet_metrics_collector::system::scripts_dir}/${metric_script_file}"
  $file_interval_seconds = $collection_frequency * 60

  $metrics_command = join([$metric_script_file_path,
                            " --metric_type ${metrics_type}",
                            " --file_interval ${file_interval_seconds}",
                            " --polling_interval ${polling_frequency_seconds}",
                            " --metrics_dir ${puppet_metrics_collector::system::output_dir}",
                            ' > /dev/null',
                            ], '')

  # The hardcoded numbers with the fqdn_rand calls are to trigger the metrics_tidy 
  # command to run at a randomly selected time between 12:00 AM and 3:00 AM.
  # NOTE - if adding a new service, the name of the service must be added to the valid_paths array in files/metrics_tidy

  $tidy_command = "${puppet_metrics_collector::scripts_dir}/metrics_tidy -d ${metrics_output_dir} -r ${retention_days}"

  file {"/etc/systemd/system/${metrics_type}-metrics.service":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/service.epp',
      { 'service' => $metrics_type, 'metrics_command' => $metrics_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file {"/etc/systemd/system/${metrics_type}-metrics.timer":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/timer.epp',
      { 'service' => $metrics_type, 'minute' => $cron_minute },
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }

  file {"/etc/systemd/system/${metrics_type}-tidy.service":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/tidy.epp',
      { 'service' => $metrics_type, 'tidy_command' => $tidy_command }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  file {"/etc/systemd/system/${metrics_type}-tidy.timer":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/tidy_timer.epp',
      { 'service' => $metrics_type }
    ),
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }

  service { "${metrics_type}-metrics.service":
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { "${metrics_type}-metrics.timer":
    ensure    => $service_ensure,
    enable    => $service_enable,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File["/etc/systemd/system/${metrics_type}-metrics.timer"],
  }

  service { "${metrics_type}-tidy.service":
    notify  => Exec['puppet_metrics_collector_daemon_reload'],
  }
  service { "${metrics_type}-tidy.timer":
    ensure    => $service_ensure,
    enable    => $service_enable,
    notify    => Exec['puppet_metrics_collector_daemon_reload'],
    subscribe => File["/etc/systemd/system/${metrics_type}-tidy.timer"],
  }

  # LEGACY CLEANUP

  cron { "${metrics_type}_metrics_tidy" :
    ensure  => absent,
  }

  cron { "${metrics_type}_metrics_collection" :
    ensure  => absent,
  }

  $metric_legacy_files = [
    "${puppet_metrics_collector::system::scripts_dir}/${metrics_type}_metrics_tidy",
  ]

  file { $metric_legacy_files :
    ensure => absent,
  }
}
