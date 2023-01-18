/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog

class TracingConfigurationE2ETests: E2ETests {
    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    /// - api-surface: Datadog.Configuration.Builder.enableTracing(_ enabled: Bool) -> Builder
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
            initializeSDK(
                trackingConsent: .granted,
                configuration: Datadog.Configuration.builderUsingE2EConfig()
                    .enableLogging(true)
                    .enableTracing(true)
                    .enableRUM(true)
                    .build()
            )
        }

        let span = Global.sharedTracer.startRootSpan(operationName: "trace_config_feature_enabled_observed_span")
        span.finish()
    }

    /// - api-surface: Datadog.Configuration.Builder.enableTracing(_ enabled: Bool) -> Builder
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
            initializeSDK(
                trackingConsent: .granted,
                configuration: Datadog.Configuration.builderUsingE2EConfig()
                    .enableLogging(true)
                    .enableTracing(true)
                    .enableRUM(true)
                    .build()
            )
        }

        let span = Global.sharedTracer.startRootSpan(operationName: "test_trace_config_feature_disabled_observed_span")
        span.finish()
    }
}
