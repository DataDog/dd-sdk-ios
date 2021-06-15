/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

class LoggingTrackingConsentE2ETests: E2ETests {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Starting With a Consent

    /// - api-surface: Datadog.initialize(appContext: AppContext,trackingConsent: TrackingConsent,configuration: Configuration)
    /// - api-surface: TrackingConsent.granted
    func test_logs_config_consent_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .granted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.initialize(appContext: AppContext,trackingConsent: TrackingConsent,configuration: Configuration)
    /// - api-surface: TrackingConsent.notGranted
    func test_logs_config_consent_NOT_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .notGranted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.initialize(appContext: AppContext,trackingConsent: TrackingConsent,configuration: Configuration)
    /// - api-surface: TrackingConsent.pending
    func test_logs_config_consent_PENDING() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .pending)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Changing Consent

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_GRANTED_to_NOT_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .granted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_GRANTED_to_PENDING() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .granted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_NOT_GRANTED_to_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .notGranted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_NOT_GRANTED_to_PENDING() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .notGranted)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }
        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_PENDING_to_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .pending)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())

        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }
    }

    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    func test_logs_config_consent_PENDING_to_NOT_GRANTED() {
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
            initializeSDK(trackingConsent: .pending)
        }
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())

        measure(spanName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }
    }
}
