/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
    func test_logs_config_feature_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
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

        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Datadog.Configuration.Builder.enableLogging(_ enabled: Bool) -> Builder
    func test_logs_config_feature_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.sdkInitialize) {
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

        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }
}
