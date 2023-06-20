/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Datadog logger.
public struct Logger {
    public struct Configuration {
        /// Format to use when printing logs to console.
        public enum ConsoleLogFormat {
            /// Prints short representation of log.
            case short
            /// Prints short representation of log with given prefix.
            case shortWith(prefix: String)
        }

        /// The service name  (default value is set to application bundle identifier)
        public var serviceName: String?

        /// The logger custom name (default value is set to main bundle identifier)
        public var loggerName: String?

        /// Enriches logs with network connection info.
        /// This means: reachability status, connection type, mobile carrier name and many more will be added to each log.
        /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
        ///
        /// `false` by default.
        public var sendNetworkInfo: Bool

        /// Enables the logs integration with RUM.
        /// If enabled all the logs will be enriched with the current RUM View information and
        /// it will be possible to see all the logs sent during a specific View lifespan in the RUM Explorer.
        ///
        /// `true` by default.
        public var bundleWithRUM: Bool

        /// Enables the logs integration with active span API from Tracing.
        /// If enabled all the logs will be bundled with the `DatadogTracer.shared().activeSpan` trace and
        /// it will be possible to see all the logs sent during that specific trace.
        ///
        /// `true` by default.
        public var bundleWithTrace: Bool

        /// Enables logs to be sent to Datadog servers.
        /// Can be used to disable sending logs in development.
        /// See also: `printLogsToConsole(_:)`.
        ///
        /// `true` by default.
        public var sendLogsToDatadog: Bool

        /// Format to use when printing logs to console - either `.short` or `.json`.
        ///
        /// Do not print to console by default.
        public var consoleLogFormat: ConsoleLogFormat?

        /// Set the minimum log level reported to Datadog servers.
        /// Any log with a level equal or above the threshold will be sent.
        ///
        /// Note: this setting doesn't impact logs printed to the console if `printLogsToConsole(_:)`
        /// is used - all logs will be printed, no matter of their level.
        ///
        /// `LogLevel.debug` by default
        public var datadogReportingThreshold: LogLevel

        /// Creates a Logger Configuration
        /// - Parameters:
        ///   - serviceName: The service name  (default value is set to application bundle identifier)
        ///   - loggerName: The logger custom name (default value is set to main bundle identifier)
        ///   - sendNetworkInfo: Enriches logs with network connection info. `false` by default.
        ///   - bundleWithRUM: Enables the logs integration with RUM. `true` by default.
        ///   - bundleWithTrace: Enables the logs integration with active span API from Tracing. `true` by default
        ///   - sendLogsToDatadog: Enables logs to be sent to Datadog servers. `true` by default.
        ///   - consoleLogFormat: Format to use when printing logs to console - either `.short` or `.json`.
        ///   - datadogReportingThreshold: Set the minimum log level reported to Datadog servers. .debug by default.
        public init(
            serviceName: String? = nil,
            loggerName: String? = nil,
            sendNetworkInfo: Bool = false,
            bundleWithRUM: Bool = true,
            bundleWithTrace: Bool = true,
            sendLogsToDatadog: Bool = true,
            consoleLogFormat: ConsoleLogFormat? = nil,
            datadogReportingThreshold: LogLevel = .debug
        ) {
            self.serviceName = serviceName
            self.loggerName = loggerName
            self.sendNetworkInfo = sendNetworkInfo
            self.bundleWithRUM = bundleWithRUM
            self.bundleWithTrace = bundleWithTrace
            self.sendLogsToDatadog = sendLogsToDatadog
            self.consoleLogFormat = consoleLogFormat
            self.datadogReportingThreshold = datadogReportingThreshold
        }
    }
    
    // MARK: - Logger Creation

    /// Creates a Logger complying with `LoggerProtocol`.
    ///
    /// - Parameters:
    ///   - configuration: The logger configuration.
    ///   - core: The instance of Datadog SDK to enable Logs in (global instance by default).
    /// - Returns: A logger instance.
    public static func create(
        with configuration: Configuration = .init(),
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> LoggerProtocol {
        do {
            return try createOrThrow(with: configuration, in: core)
        } catch {
            DD.logger.critical("Failed to build `Logger`.", error: error)
            return NOPLogger()
        }
    }

    /// Creates a Logger complying with `LoggerProtocol` or throw an error.
    ///
    /// - Parameters:
    ///   - configuration: The logger configuration.
    ///   - core: The instance of Datadog SDK to enable Logs in (global instance by default).
    /// - Returns: A logger instance.
    private static func createOrThrow(with configuration: Configuration, in core: DatadogCoreProtocol) throws -> LoggerProtocol {
        if core is NOPDatadogCore {
            throw ProgrammerError(
                description: "`Datadog.initialize()` must be called prior to `Logger.builder.build()`."
            )
        }

        guard let feature = core.get(feature: LogsFeature.self) else {
            throw ProgrammerError(
                description: "`Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
            )
        }

        let remoteLogger: RemoteLogger? = {
            guard configuration.sendLogsToDatadog else {
                return nil
            }

            return RemoteLogger(
                core: core,
                configuration: RemoteLogger.Configuration(
                    service: configuration.serviceName,
                    loggerName: configuration.loggerName,
                    sendNetworkInfo: configuration.sendNetworkInfo,
                    threshold: configuration.datadogReportingThreshold,
                    eventMapper: feature.logEventMapper,
                    sampler: feature.sampler
                ),
                dateProvider: feature.dateProvider,
                rumContextIntegration: configuration.bundleWithRUM,
                activeSpanIntegration: configuration.bundleWithTrace
            )
        }()

        let consoleLogger: ConsoleLogger? = {
            guard let consoleLogFormat = configuration.consoleLogFormat else {
                return nil
            }

            return ConsoleLogger(
                configuration: ConsoleLogger.Configuration(
                    timeZone: .current,
                    format: consoleLogFormat
                ),
                dateProvider: feature.dateProvider,
                printFunction: consolePrint
            )
        }()

        switch (remoteLogger, consoleLogger) {
        case (let remoteLogger?, nil):
            return remoteLogger

        case (nil, let consoleLogger?):
            return consoleLogger

        case (let remoteLogger?, let consoleLogger?):
            return CombinedLogger(combinedLoggers: [remoteLogger, consoleLogger])

        case (nil, nil): // when user explicitly produces a no-op logger
            return NOPLogger()
        }
    }
}
