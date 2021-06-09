define puppet_metrics_collector::collect (
  String $metrics_type    = $title,
  String $metrics_command = undef,
  String $tidy_command    = undef,
  String $metric_ensure   = 'present',
  String $minute          = '5',
) {

  $service_ensure = $metric_ensure ? {
    'present' => running,
    'absent'  => stopped,
  }

  $service_enable = $metric_ensure ? {
    'present' => true,
    'absent'  => false,
  }

  file {"/etc/systemd/system/${metrics_type}-metrics.service":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/service.epp',
      { 'service' => $metrics_type, 'metrics_command' => $metrics_command }
    ),
  }
  file {"/etc/systemd/system/${metrics_type}-metrics.timer":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/timer.epp',
      { 'service' => $metrics_type, 'minute' => $minute },
    ),
  }

  file {"/etc/systemd/system/${metrics_type}-tidy.service":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/tidy.epp',
      { 'service' => $metrics_type, 'tidy_command' => $tidy_command }
    ),
  }
  file {"/etc/systemd/system/${metrics_type}-tidy.timer":
    ensure  => $metric_ensure,
    content => epp('puppet_metrics_collector/tidy_timer.epp',
      { 'service' => $metrics_type }
    ),
  }

  service { "${metrics_type}-metrics.service":
  }
  service { "${metrics_type}-metrics.timer":
    ensure    => $service_ensure,
    enable    => $service_enable,
    subscribe => File["/etc/systemd/system/${metrics_type}-metrics.timer"],
  }

  service { "${metrics_type}-tidy.service": }
  service { "${metrics_type}-tidy.timer":
    ensure    => $service_ensure,
    enable    => $service_enable,
    subscribe => File["/etc/systemd/system/${metrics_type}-tidy.timer"],
  }
}
