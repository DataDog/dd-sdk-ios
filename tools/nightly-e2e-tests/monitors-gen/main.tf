# This file is auto-generated, do not edit it directly

terraform {
  required_providers {
    datadog = {
      source = "DataDog/datadog"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

# Monitors:

resource "datadog_monitor" logs_config_consent_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_granted: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_config_consent_not_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_not_granted: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_config_consent_pending_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_pending: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_config_consent_granted_to_not_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_granted_to_not_granted: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted_to_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_config_consent_granted_to_pending_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_granted_to_pending: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted_to_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_config_consent_not_granted_to_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_not_granted_to_granted: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted_to_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_config_consent_not_granted_to_pending_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_not_granted_to_pending: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted_to_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_config_consent_pending_to_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_pending_to_granted: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending_to_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_config_consent_pending_to_not_granted_data {
  name               = "[RUM] [iOS] Nightly - logs_config_consent_pending_to_not_granted: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending_to_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_logger_builder_set_service_name_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_set_service_name: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly.custom @test_method_name:logs_logger_builder_set_service_name\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_set_logger_name_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_set_logger_name: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_set_logger_name @logger.name:custom_logger_name\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_send_network_info_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_send_network_info_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_network_info_enabled @network.client.reachability:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_send_network_info_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_send_network_info_disabled: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_network_info_disabled @network.client.reachability:*\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_logger_builder_send_logs_to_datadog_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_send_logs_to_datadog_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_logs_to_datadog_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_send_logs_to_datadog_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_send_logs_to_datadog_disabled: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_logs_to_datadog_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_logger_builder_print_logs_to_console_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_print_logs_to_console_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_print_logs_to_console_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_print_logs_to_console_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_print_logs_to_console_disabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_print_logs_to_console_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_bundle_with_rum_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_rum_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_rum_enabled @application_id:* @session_id:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_bundle_with_rum_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_rum_disabled: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_rum_disabled @application_id:* @session_id:* view.id:*\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" logs_logger_builder_bundle_with_trace_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_trace_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_trace_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_builder_bundle_with_trace_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_trace_disabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_trace_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_debug_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_debug_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_debug_log status:debug\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_debug_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_debug_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_debug_log{env:instrumentation,resource_name:logs_logger_debug_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_debug_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_debug_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_debug_log_with_error status:debug\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_debug_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_debug_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_debug_log_with_error{env:instrumentation,resource_name:logs_logger_debug_log_with_error*,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_info_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_info_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_info_log status:debug\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_info_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_info_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_info_log{env:instrumentation,resource_name:logs_logger_info_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_info_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_info_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_info_log_with_error status:info\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_info_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_info_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_info_log_with_error{env:instrumentation,resource_name:logs_logger_info_log_with_error,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_notice_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_notice_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_notice_log status:notice\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_notice_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_notice_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_notice_log{env:instrumentation,resource_name:logs_logger_notice_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_notice_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_notice_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_notice_log_with_error status:notice\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_notice_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_notice_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_notice_log{env:instrumentation,resource_name:logs_logger_notice_log_with_error,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_warn_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_warn_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_warn_log status:warn\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_warn_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_warn_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_warn_log{env:instrumentation,resource_name:logs_logger_warn_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_warn_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_warn_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_warn_log_with_error status:warn\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_warn_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_warn_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_warn_log_with_error{env:instrumentation,resource_name:logs_logger_warn_log_with_error,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_error_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_error_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_error_log status:error\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_error_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_error_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_error_log{env:instrumentation,resource_name:logs_logger_error_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_error_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_error_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_error_log_with_error status:error\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_error_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_error_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_error_log_with_error{env:instrumentation,resource_name:logs_logger_error_log_with_error,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_critical_log_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_critical_log: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_critical_log status:critical\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_critical_log_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_critical_log: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_critical_log{env:instrumentation,resource_name:logs_logger_critical_log,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_critical_log_with_error_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_critical_log_with_error: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_critical_log_with_error status:critical\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_critical_log_with_error_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_critical_log_with_error: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_critical_log_with_error{env:instrumentation,resource_name:logs_logger_critical_log_with_error,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_string_attribute_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_string_attribute: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_string_attribute @test_special_string_attribute:customAttribute*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_string_attribute_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_string_attribute: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_string_attribute{env:instrumentation,resource_name:logs_logger_add_string_attribute,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_int_attribute_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_int_attribute: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_int_attribute @test_special_int_attribute:>10\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_int_attribute_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_int_attribute: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_int_attribute{env:instrumentation,resource_name:logs_logger_add_int_attribute,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_double_attribute_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_double_attribute: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_double_attribute @test_special_double_attribute:>10\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_double_attribute_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_double_attribute: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_double_attribute{env:instrumentation,resource_name:logs_logger_add_double_attribute,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_bool_attribute_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_bool_attribute: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_bool_attribute @test_special_bool_attribute:(true OR false)\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_bool_attribute_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_bool_attribute: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_bool_attribute{env:instrumentation,resource_name:logs_logger_add_bool_attribute,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_remove_attribute_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_remove_attribute: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_attribute -@test_special_string_attribute:* -@test_special_int_attribute:* -@test_special_double_attribute:*  -@test_special_bool_attribute:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_remove_attribute_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_remove_attribute: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_remove_attribute{env:instrumentation,resource_name:logs_logger_remove_attribute,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_tag_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_tag: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_tag test_special_tag:customTag*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_tag_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_tag: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_tag{env:instrumentation,resource_name:logs_logger_add_tag,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_add_already_formatted_tag_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_add_already_formatted_tag: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_add_already_formatted_tag test_special_tag:customTag*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_add_already_formatted_tag_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_add_already_formatted_tag: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_add_already_formatted_tag{env:instrumentation,resource_name:logs_logger_add_already_formatted_tag,service:com.datadog.ios.nightly} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_remove_tag_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_remove_tag: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_tag -test_special_tag:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_remove_tag_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_remove_tag: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_remove_tag{env:instrumentation,service:com.datadog.ios.nightly,resource_name:logs_logger_remove_tag} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_logger_remove_already_formatted_tag_data {
  name               = "[RUM] [iOS] Nightly - logs_logger_remove_already_formatted_tag: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_remove_already_formatted_tag -test_special_tag:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_logger_remove_already_formatted_tag_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_remove_already_formatted_tag: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):p50:trace.logs_logger_remove_already_formatted_tag{env:instrumentation,service:com.datadog.ios.nightly,resource_name:logs_logger_remove_already_formatted_tag} > 0.024"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.024
  }

}

resource "datadog_monitor" logs_config_feature_enabled_data {
  name               = "[RUM] [iOS] Nightly - logs_config_feature_enabled: number of logs is below expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_feature_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 1.0
  }

}

resource "datadog_monitor" logs_config_feature_disabled_data {
  name               = "[RUM] [iOS] Nightly - logs_config_feature_disabled: number of logs is above expected value"
  type               = "log alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query             = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_feature_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
  notify_no_data    = false
  renotify_interval = 0
  notify_audit      = false
  timeout_h         = 0
  include_tags      = true
  new_host_delay    = 300
  monitor_thresholds {
    critical = 0.0
  }

}

resource "datadog_monitor" sdk_initialize_performance {
  name               = "[RUM] [iOS] Nightly Performance - sdk_initialize: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):avg:trace.sdk_initialize.duration{env:instrumentation,resource_name:sdk_initialize,service:com.datadog.ios.nightly} > 0.016"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.016
  }

}

resource "datadog_monitor" sdk_set_tracking_consent_performance {
  name               = "[RUM] [iOS] Nightly Performance - sdk_set_tracking_consent: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):avg:trace.sdk_set_tracking_consent.duration{env:instrumentation,resource_name:sdk_set_tracking_consent,service:com.datadog.ios.nightly} > 0.016"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.016
  }

}

resource "datadog_monitor" logs_logger_initialize_performance {
  name               = "[RUM] [iOS] Nightly Performance - logs_logger_initialize: has a high average execution time"
  type               = "query alert"
  tags               = ["service:com.datadog.ios.nightly", "env:instrumentation", "team:rumm", "source:ios", ]
  message            = <<EOT
@maciek.grzybowski@datadoghq.com
@mert.buran@datadoghq.com
EOT
  escalation_message = <<EOT
<nil>
EOT

  query               = "avg(last_1d):avg:trace.logs_logger_initialize.duration{env:instrumentation,resource_name:logs_logger_initialize,service:com.datadog.ios.nightly} > 0.016"
  notify_no_data      = false
  renotify_interval   = 0
  notify_audit        = false
  timeout_h           = 0
  include_tags        = true
  require_full_window = false
  new_host_delay      = 300
  monitor_thresholds {
    critical = 0.016
  }

}

