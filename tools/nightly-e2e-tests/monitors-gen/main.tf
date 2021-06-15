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

