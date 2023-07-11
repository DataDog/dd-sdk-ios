/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogLogs

class LogsTrackingConsentE2ETests: E2ETests {
    private var logger: LoggerProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Common Monitors

    /// - common performance monitor - measures `Datadog.set(trackingConsent:)` performance:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = sdk_set_tracking_consent_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - sdk_set_tracking_consent: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:sdk_set_tracking_consent,service:com.datadog.ios.nightly} > 0.016"
    /// $monitor_threshold = 0.016
    /// ```

    // MARK: - Starting With a Consent

    /// - api-surface: Datadog.initialize(with : Configuration, trackingConsent: TrackingConsent)
    /// - api-surface: TrackingConsent.granted
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_granted: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_config_consent_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.initialize(with : Configuration, trackingConsent: TrackingConsent)
    /// - api-surface: TrackingConsent.notGranted
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_not_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_not_granted: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_NOT_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.initialize(with : Configuration, trackingConsent: TrackingConsent)
    /// - api-surface: TrackingConsent.pending
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_pending_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_pending: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_PENDING() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Changing Consent

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_granted_to_not_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_granted_to_not_granted: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted_to_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_GRANTED_to_NOT_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_granted_to_pending_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_granted_to_pending: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_granted_to_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_GRANTED_to_PENDING() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_not_granted_to_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_not_granted_to_granted: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted_to_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_config_consent_NOT_GRANTED_to_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_not_granted_to_pending_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_not_granted_to_pending: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_not_granted_to_pending\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_NOT_GRANTED_to_PENDING() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_pending_to_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_pending_to_granted: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending_to_granted\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_config_consent_PENDING_to_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }

        logger.sendRandomLog(with: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor - we assert that no data is delivered in this monitor:
    /// ```logs
    /// $monitor_id = logs_config_consent_pending_to_not_granted_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_config_consent_pending_to_not_granted: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_config_consent_pending_to_not_granted\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_config_consent_PENDING_to_NOT_GRANTED() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            Logs.enable()
        }
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.create()
        }

        logger.sendRandomLog(with: DD.logAttributes())

        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }
    }
}
