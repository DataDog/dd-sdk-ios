/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog
import DatadogCrashReporting

class LoggingConfigurationE2ETests: E2ETests {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    /// - api-surface: Datadog.Configuration.Builder.enableLogging(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_config_feature_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_feature_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_feature_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_config_feature_enabled() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(
                trackingConsent: .granted,
                configuration: Datadog.Configuration.builderUsingE2EConfig()
                    .enableLogging(true)
                    .enableTracing(true)
                    .enableRUM(true)
                    .enableCrashReporting(using: DDCrashReportingPlugin())
                    .build()
            )
        }

        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.Configuration.Builder.enableLogging(_ enabled: Bool) -> Builder
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_feature_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_feature_disabled: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_feature_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_feature_disabled() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(
                trackingConsent: .granted,
                configuration: Datadog.Configuration.builderUsingE2EConfig()
                    .enableLogging(false)
                    .enableTracing(true)
                    .enableRUM(true)
                    .enableCrashReporting(using: DDCrashReportingPlugin())
                    .build()
            )
        }

        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }
}
