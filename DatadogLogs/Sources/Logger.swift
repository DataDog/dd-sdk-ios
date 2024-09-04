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
        public var service: String?

        /// The logger custom name (default value is set to main bundle identifier)
        public var name: String?

        /// Enriches logs with network connection info.
        ///
        /// This means: reachability status, connection type, mobile carrier name and many more will be added to each log.
        /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
        ///
        /// `false` by default.
        public var networkInfoEnabled: Bool

        /// Enables the logs integration with RUM.
        ///
        /// If enabled all the logs will be enriched with the current RUM View information and
        /// it will be possible to see all the logs sent during a specific View lifespan in the RUM Explorer.
        ///
        /// `true` by default.
        public var bundleWithRumEnabled: Bool

        /// Enables the logs integration with active span API from Tracing.
        ///
        /// If enabled all the logs will be bundled with the `DatadogTracer.shared().activeSpan` trace and
        /// it will be possible to see all the logs sent during that specific trace.
        ///
        /// `true` by default.
        public var bundleWithTraceEnabled: Bool

        /// Sets the sample rate for remote logging.
        ///
        /// **When set to `0`, no log entries will be sent to Datadog servers.**
        /// A value of`100` means all logs will be processed.
        ///
        /// When setting the `remoteSampleRate` to `0`
        ///
        /// Default is `100`, meaning that all logs will be sent.
        public var remoteSampleRate: Float

        /// Set the minimum log level reported to Datadog servers.
        /// Any log with a level equal or above the threshold will be sent.
        ///
        /// Note: this setting doesn't impact logs printed to the console if `printLogsToConsole(_:)`
        /// is used - all logs will be printed, no matter of their level.
        ///
        /// `LogLevel.debug` by default
        public var remoteLogThreshold: LogLevel

        /// Format to use when printing logs to console - either `.short` or `.json`.
        ///
        /// Do not print to console by default.
        public var consoleLogFormat: ConsoleLogFormat?

        /// Overrides the current process info.
        internal var processInfo: ProcessInfo = .processInfo

        /// Creates a Logger Configuration.
        /// 
        /// - Parameters:
        ///   - service: The service name  (default value is set to application bundle identifier)
        ///   - name: The logger custom name (default value is set to main bundle identifier)
        ///   - networkInfoEnabled: Enriches logs with network connection info. `false` by default.
        ///   - bundleWithRUM: Enables the logs integration with RUM. `true` by default.
        ///   - bundleWithTraceEnabled: Enables the logs integration with active span API from Tracing. `true` by default
        ///   - remoteSampleRate: The sample rate for remote logging. **When set to `0`, no log entries will be sent to Datadog servers.**
        ///   - remoteLogThreshold: Set the minimum log level reported to Datadog servers. .debug by default.
        ///   - consoleLogFormat: Format to use when printing logs to console - either `.short` or `.json`.
        public init(
            service: String? = nil,
            name: String? = nil,
            networkInfoEnabled: Bool = false,
            bundleWithRumEnabled: Bool = true,
            bundleWithTraceEnabled: Bool = true,
            remoteSampleRate: Float = 100,
            remoteLogThreshold: LogLevel = .debug,
            consoleLogFormat: ConsoleLogFormat? = nil
        ) {
            self.service = service
            self.name = name
            self.networkInfoEnabled = networkInfoEnabled
            self.bundleWithRumEnabled = bundleWithRumEnabled
            self.bundleWithTraceEnabled = bundleWithTraceEnabled
            self.remoteSampleRate = remoteSampleRate
            self.remoteLogThreshold = remoteLogThreshold
            self.consoleLogFormat = consoleLogFormat
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
                description: "`Datadog.initialize()` must be called prior to `Logger.create()`."
            )
        }

        guard let feature = core.get(feature: LogsFeature.self) else {
            throw ProgrammerError(
                description: "`Logger.create()` produces a non-functional logger because the `Logs` feature was not enabled."
            )
        }

        let debug = configuration.processInfo.arguments.contains(LaunchArguments.Debug)

        let remoteLogger: RemoteLogger? = {
            guard configuration.remoteSampleRate > 0 else {
                return nil
            }

            return RemoteLogger(
                featureScope: core.scope(for: LogsFeature.self),
                core: core,
                configuration: RemoteLogger.Configuration(
                    service: configuration.service,
                    name: configuration.name,
                    networkInfoEnabled: configuration.networkInfoEnabled,
                    threshold: configuration.remoteLogThreshold,
                    eventMapper: feature.logEventMapper,
                    sampler: Sampler(samplingRate: debug ? 100 : configuration.remoteSampleRate)
                ),
                dateProvider: feature.dateProvider,
                rumContextIntegration: configuration.bundleWithRumEnabled,
                activeSpanIntegration: configuration.bundleWithTraceEnabled
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
