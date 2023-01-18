/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog

class LoggerBuilderE2ETests: E2ETests {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Common Monitors

    /// - common performance monitor - measures `Logger.builder.build()` performance:
    /// ```apm
    /// $feature = logs
    /// $monitor_id = logs_logger_initialize_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - logs_logger_initialize: has a high average execution time"
    /// $monitor_query = "avg(last_1d):avg:trace.perf_measure{env:instrumentation,resource_name:logs_logger_initialize,service:com.datadog.ios.nightly} > 0.016"
    /// $monitor_threshold = 0.016
    /// ```

    // MARK: - Enabling Options

    /// - api-surface: Logger.Builder.set(serviceName: String) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_set_service_name_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_set_service_name: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly.custom @test_method_name:logs_logger_builder_set_service_name\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_set_SERVICE_NAME() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.set(serviceName: "com.datadog.ios.nightly.custom").build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.set(loggerName: String) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_set_logger_name_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_set_logger_name: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_set_logger_name @logger.name:custom_logger_name\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_set_LOGGER_NAME() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.set(loggerName: "custom_logger_name").build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendNetworkInfo(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_send_network_info_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_send_network_info_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_network_info_enabled @network.client.reachability:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_SEND_NETWORK_INFO_enabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendNetworkInfo(true).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendNetworkInfo(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_send_network_info_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_send_network_info_disabled: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_network_info_disabled @network.client.reachability:*\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_logger_builder_SEND_NETWORK_INFO_disabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendNetworkInfo(false).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Choosing Logs Output

    /// - api-surface: Logger.Builder.sendLogsToDatadog(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_send_logs_to_datadog_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_send_logs_to_datadog_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_logs_to_datadog_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_SEND_LOGS_TO_DATADOG_enabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendLogsToDatadog(true).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.sendLogsToDatadog(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_send_logs_to_datadog_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_send_logs_to_datadog_disabled: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_send_logs_to_datadog_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_logger_builder_SEND_LOGS_TO_DATADOG_disabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.sendLogsToDatadog(false).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Builder
    ///
    /// - data monitor - as long as sending logs to Datadog is enabled (which is default), this this monitor should receive data:
    /// ```logs
    /// $monitor_id = logs_logger_builder_print_logs_to_console_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_print_logs_to_console_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_print_logs_to_console_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_PRINT_LOGS_TO_CONSOLE_enabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.printLogsToConsole(true, usingFormat: .random()).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    /// - api-surface: Logger.Builder.printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Builder
    ///
    /// - data monitor - as long as sending logs to Datadog is enabled (which is default), this this monitor should receive data:
    /// ```logs
    /// $monitor_id = logs_logger_builder_print_logs_to_console_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_print_logs_to_console_disabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_print_logs_to_console_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_PRINT_LOGS_TO_CONSOLE_disabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.printLogsToConsole(false, usingFormat: .random()).build()
        }

        logger.sendRandomLog(with: DD.logAttributes())
    }

    // MARK: - Bundling With Other Features

    /// - api-surface: Logger.Builder.bundleWithRUM(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_bundle_with_rum_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_rum_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_rum_enabled @application_id:* @session_id:*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_BUNDLE_WITH_RUM_enabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithRUM(true).build()
        }

        let viewKey: String = .mockRandom()
        Global.rum.startView(key: viewKey)
        Global.rum.dd.flush()
        logger.sendRandomLog(with: DD.logAttributes())
        Global.rum.stopView(key: viewKey)
    }

    /// - api-surface: Logger.Builder.bundleWithRUM(_ enabled: Bool) -> Builder
    ///
    /// - data monitor:
    /// ```logs
    /// $monitor_id = logs_logger_builder_bundle_with_rum_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_rum_disabled: number of logs is above expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_rum_disabled @application_id:* @session_id:* view.id:*\").index(\"*\").rollup(\"count\").last(\"1d\") > 0"
    /// $monitor_threshold = 0.0
    /// $notify_no_data = false
    /// ```
    func test_logs_logger_builder_BUNDLE_WITH_RUM_disabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
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
    ///
    /// - data monitor - unfortunately we can't assert any APM trait in this monitor, so we just check if the data comes in:
    /// ```logs
    /// $monitor_id = logs_logger_builder_bundle_with_trace_enabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_trace_enabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_trace_enabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_BUNDLE_WITH_TRACE_enabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithTrace(true).build()
        }

        let activeSpan = Global.sharedTracer
            .startRootSpan(operationName: .mockRandom())
            .setActive()
        logger.sendRandomLog(with: DD.logAttributes())
        activeSpan.finish()
    }

    /// - api-surface: Logger.Builder.bundleWithTrace(_ enabled: Bool) -> Builder
    ///
    /// - data monitor - unfortunately we can't assert any APM trait in this monitor, so we just check if the data comes in:
    /// ```logs
    /// $monitor_id = logs_logger_builder_bundle_with_trace_disabled_data
    /// $monitor_name = "[RUM] [iOS] Nightly - logs_logger_builder_bundle_with_trace_disabled: number of logs is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:logs_logger_builder_bundle_with_trace_disabled\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    func test_logs_logger_builder_BUNDLE_WITH_TRACE_disabled() {
        measure(resourceName: DD.PerfSpanName.loggerInitialize) {
            logger = Logger.builder.bundleWithTrace(false).build()
        }

        let activeSpan = Global.sharedTracer
            .startRootSpan(operationName: .mockRandom())
            .setActive()
        logger.sendRandomLog(with: DD.logAttributes())
        activeSpan.finish()
    }
}
