/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

class LoggerBuilderE2ETests: E2ETests {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Enabling Options

    /// - api-surface: Logger.Builder.set(serviceName: String) -> Builder
    func test_logs_logger_builder_set_SERVICE_NAME() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.set(serviceName: "com.datadog.ios.nightly.custom").build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.set(loggerName: String) -> Builder
    func test_logs_logger_builder_set_LOGGER_NAME() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.set(loggerName: "custom_logger_name").build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendNetworkInfo(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_SEND_NETWORK_INFO_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendNetworkInfo(true).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendNetworkInfo(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_SEND_NETWORK_INFO_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendNetworkInfo(false).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Choosing Logs Output

    /// - api-surface: Logger.Builder.sendLogsToDatadog(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_SEND_LOGS_TO_DATADOG_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendLogsToDatadog(true).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendLogsToDatadog(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_SEND_LOGS_TO_DATADOG_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendLogsToDatadog(false).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Builder
    func test_logs_logger_builder_PRINT_LOGS_TO_CONSOLE_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.printLogsToConsole(true, usingFormat: .random()).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Builder
    func test_logs_logger_builder_PRINT_LOGS_TO_CONSOLE_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.printLogsToConsole(false, usingFormat: .random()).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Bundling With Other Features

    /// - api-surface: Logger.Builder.bundleWithRUM(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_BUNDLE_WITH_RUM_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithRUM(true).build()
        }

        let viewKey: String = .mockRandom()
        Global.rum.startView(key: viewKey)
        Global.rum.dd.flush()
        logger.sendRandomLog(with: DD.logAttributes())
        Global.rum.stopView(key: viewKey)
    }

    /// - api-surface: Logger.Builder.bundleWithRUM(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_BUNDLE_WITH_RUM_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithRUM(false).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())

        let viewKey: String = .mockRandom()
        Global.rum.startView(key: viewKey)
        Global.rum.dd.flush()
        logger.sendRandomLog(with: DD.logAttributes())
        Global.rum.stopView(key: viewKey)
    }

    /// - api-surface: Logger.Builder.bundleWithTrace(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_BUNDLE_WITH_TRACE_enabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithTrace(true).build()
        }

        let activeSpan = Global.sharedTracer
            .startRootSpan(operationName: .mockRandom())
            .setActive()
        logger.sendRandomLog(with: DD.logAttributes())
        activeSpan.finish()
    }

    /// - api-surface: Logger.Builder.bundleWithTrace(_ enabled: Bool) -> Builder
    func test_logs_logger_builder_BUNDLE_WITH_TRACE_disabled() { // E2E:wip
        measure(spanName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithTrace(false).build()
        }

        let activeSpan = Global.sharedTracer
            .startRootSpan(operationName: .mockRandom())
            .setActive()
        logger.sendRandomLog(with: DD.logAttributes())
        activeSpan.finish()
    }
}
