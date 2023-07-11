/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogLogs
import DatadogRUM
import DatadogTrace
import DatadogCrashReporting

class LogsConfigurationE2ETests: E2ETests {
    private var logger: LoggerProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    /// - api-surface: Logs.enable()
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_config_feature_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_feature_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_feature_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_config_feature_enabled() {
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

        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logs.enable()
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
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Trace.enable()
            RUM.enable(with: .e2e)
            CrashReporting.enable()
        }

        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }
}
