/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `DatadogLogger` builder.
///
/// Usage:
///
///     DatadogLogger.builder
///         ... // customize using builder methods
///         .build()
///
public class Builder {
    internal var serviceName: String? = nil
    internal var loggerName: String? = nil
    internal var sendNetworkInfo = false
    internal var bundleWithRUM = true
    internal var bundleWithTrace = true
    internal var sendLogsToDatadog = true
    internal var consoleLogFormat: ConsoleLogFormat? = nil
    internal var datadogReportingThreshold: LogLevel = .debug

    /// Sets the service name that will appear in logs.
    /// - Parameter serviceName: the service name  (default value is set to application bundle identifier)
    public func set(serviceName: String) -> Self {
        self.serviceName = serviceName
        return self
    }

    /// Sets the logger name that will appear in logs.
    /// - Parameter loggerName: the logger custom name (default value is set to main bundle identifier)
    public func set(loggerName: String) -> Self {
        self.loggerName = loggerName
        return self
    }

    /// Enriches logs with network connection info.
    /// This means: reachability status, connection type, mobile carrier name and many more will be added to each log.
    /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
    /// - Parameter enabled: `false` by default
    public func sendNetworkInfo(_ enabled: Bool) -> Self {
        sendNetworkInfo = enabled
        return self
    }

    /// Enables the logs integration with RUM.
    /// If enabled all the logs will be enriched with the current RUM View information and
    /// it will be possible to see all the logs sent during a specific View lifespan in the RUM Explorer.
    /// - Parameter enabled: `true` by default
    public func bundleWithRUM(_ enabled: Bool) -> Self {
        bundleWithRUM = enabled
        return self
    }

    /// Enables the logs integration with active span API from Tracing.
    /// If enabled all the logs will be bundled with the `DatadogTracer.shared().activeSpan` trace and
    /// it will be possible to see all the logs sent during that specific trace.
    /// - Parameter enabled: `true` by default
    public func bundleWithTrace(_ enabled: Bool) -> Self {
        bundleWithTrace = enabled
        return self
    }

    /// Enables logs to be sent to Datadog servers.
    /// Can be used to disable sending logs in development.
    /// See also: `printLogsToConsole(_:)`.
    /// - Parameter enabled: `true` by default
    public func sendLogsToDatadog(_ enabled: Bool) -> Self {
        self.sendLogsToDatadog = enabled
        return self
    }

    /// Set the minim log level reported to Datadog servers.
    /// Any log with a level equal or above the threshold will be sent.
    ///
    /// Note: this setting doesn't impact logs printed to the console if `printLogsToConsole(_:)`
    /// is used - all logs will be printed, no matter of their level.
    ///
    /// - Parameter datadogReportingThreshold: `LogLevel.debug` by default
    public func set(datadogReportingThreshold: LogLevel) -> Self {
        self.datadogReportingThreshold = datadogReportingThreshold
        return self
    }

    /// Format to use when printing logs to console if `printLogsToConsole(_:)` is enabled.
    public enum ConsoleLogFormat {
        /// Prints short representation of log.
        case short
        /// Prints short representation of log with given prefix.
        case shortWith(prefix: String)

        // MARK: - Deprecated

        @available(*, deprecated, message: """
        JSON format is no longer supported for console logs and this API will be removed in future versions
        of the SDK. The `.short` format will be used instead.
        """)
        public static let json: ConsoleLogFormat = .short

        @available(*, deprecated, message: """
        JSON format is no longer supported for console logs and this API will be removed in future versions
        of the SDK. The `.shortWith(prefix:)` format will be used instead.
        """)
        public static func jsonWith(prefix: String) -> ConsoleLogFormat {
            return .shortWith(prefix: prefix)
        }
    }

    /// Enables  logs to be printed to debugger console.
    /// Can be used in development instead of sending logs to Datadog servers.
    /// See also: `sendLogsToDatadog(_:)`.
    /// - Parameters:
    ///   - enabled: `false` by default
    ///   - format: format to use when printing logs to console - either `.short` or `.json` (`.short` is default)
    public func printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Self {
        consoleLogFormat = enabled ? format : nil
        return self
    }

    /// Builds `DatadogLogger` object.
    public func build(in core: DatadogCoreProtocol = CoreRegistry.default) -> DatadogLogger {
        do {
            let logger = try buildOrThrow(in: core)
            return DatadogLogger(logger)
        } catch {
            DD.logger.critical("Failed to build `Logger`.", error: error)
            return DatadogLogger(NOPLogger())
        }
    }

    private func buildOrThrow(in core: DatadogCoreProtocol) throws -> Logger {
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
            guard sendLogsToDatadog else {
                return nil
            }

            let configuration = RemoteLogger.Configuration(
                service: serviceName,
                loggerName: loggerName ?? feature.applicationBundleIdentifier,
                sendNetworkInfo: sendNetworkInfo,
                threshold: datadogReportingThreshold,
                eventMapper: feature.logEventMapper,
                sampler: feature.sampler
            )

            return RemoteLogger(
                core: core,
                configuration: configuration,
                dateProvider: feature.dateProvider,
                rumContextIntegration: bundleWithRUM,
                activeSpanIntegration: bundleWithTrace
            )
        }()

        let consoleLogger: ConsoleLogger? = {
            guard let consoleLogFormat = consoleLogFormat else {
                return nil
            }

            let configuration = ConsoleLogger.Configuration(
                timeZone: .current,
                format: consoleLogFormat
            )

            return ConsoleLogger(
                configuration: configuration,
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
