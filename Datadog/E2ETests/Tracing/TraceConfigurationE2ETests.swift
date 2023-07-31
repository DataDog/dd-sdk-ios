/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogTrace
import DatadogLogs
import DatadogRUM
import DatadogCrashReporting

class TraceConfigurationE2ETests: E2ETests {
    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    /// - api-surface: Trace.enable()
    ///
    /// - data monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_config_feature_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_config_feature_enabled: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:trace.trace_config_feature_enabled_observed_span.hits{service:com.datadog.ios.nightly,env:instrumentation}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    func test_trace_config_feature_enabled() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Logs.enable()
            Trace.enable()
            RUM.enable(with: .e2e)
            CrashReporting.enable()
        }

        let span = Tracer.shared().startRootSpan(operationName: "trace_config_feature_enabled_observed_span")
        span.finish()
    }

    /// - api-surface: Trace.enable()
    ///
    /// - data monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_config_feature_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_config_feature_disabled: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:trace.trace_config_feature_disabled_observed_span.hits{service:com.datadog.ios.nightly,env:instrumentation}.as_count() > 0"
    /// $monitor_threshold = 0
    /// ```
    func test_trace_config_feature_disabled() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Logs.enable()
            RUM.enable(with: .e2e)
            CrashReporting.enable()
        }

        let span = Tracer.shared().startRootSpan(operationName: "test_trace_config_feature_disabled_observed_span")
        span.finish()
    }
}
