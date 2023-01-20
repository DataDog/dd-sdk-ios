/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Log levels ordered by their severity, with `.debug` being the least severe and
/// `.critical` being the most severe.
public enum LogLevel: Int, Codable {
    case debug
    case info
    case notice
    case warn
    case error
    case critical
}

/// Because `Logger` is a common name widely used across different projects, the `Datadog.Logger` may conflict when
/// using `Logger.builder`. In such case, following `DDLogger` typealias can be used to avoid compiler ambiguity.
///
/// Usage:
///
///     import Datadog
///
///     // logger reference
///     var logger: DDLogger!
///
///     // instantiate Datadog logger
///     logger = DDLogger.builder.build()
///
public typealias DDLogger = Logger

public protocol LoggerProtocol {
    /// General purpose logging method.
    /// Sends a log with certain `level`, `message`, `error` and `attributes`.
    ///
    /// Although it can be used directly, it is more convenient and recommended to use specific methods declared on `Logger`:
    /// * `debug(_:error:attributes:)`
    /// * `info(_:error:attributes:)`
    /// * ...
    ///
    /// - Parameters:
    ///   - level: the log level
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?)

    /// General purpose logging method.
    /// Sends a log with certain `level`, `message`, `errorKind`,  `errorMessage`,  `stackTrace` and `attributes`.
    ///
    /// This method is meant for non-native or cross platform frameworks (such as React Native or Flutter) to send error information
    /// to Datadog. Although it can be used directly, it is recommended to use other methods declared on `Logger`.
    ///
    /// - Parameters:
    ///   - level: the log level
    ///   - message: the message to be logged
    ///   - errorKind: the kind of error reported
    ///   - errorMessage: the message attached to the error
    ///   - stackTrace: a string representation of the error's stack trace
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?
    )

    // MARK: - Attributes

    /// Adds a custom attribute to all future logs sent by this logger.
    /// - Parameters:
    ///   - key: the attribute key. See `AttributeKey` documentation for information on nesting attributes with dot `.` syntax.
    ///   - value: the attribute value that conforms to `Encodable`. See `AttributeValue` documentation
    ///   for information on nested encoding containers limitation.
    func addAttribute(forKey key: AttributeKey, value: AttributeValue)

    /// Removes the custom attribute from all future logs sent by this logger.
    ///
    /// Previous logs won't lose this attribute if sent prior to this call.
    /// - Parameter key: the key of an attribute that will be removed.
    func removeAttribute(forKey key: AttributeKey)

    // MARK: - Tags

    /// Adds a `"key:value"` tag to all future logs sent by this logger.
    ///
    /// Tags must start with a letter and
    /// * may contain: alphanumerics, underscores, minuses, colons, periods and slashes;
    /// * other special characters are converted to underscores;
    /// * must be lowercase
    /// * and can be at most 200 characters long (tags exceeding this limit will be truncated to first 200 characters).
    ///
    /// See also: [Defining Tags](https://docs.datadoghq.com/tagging/#defining-tags)
    ///
    /// - Parameter key: tag key
    /// - Parameter value: tag value
    func addTag(withKey key: String, value: String)

    /// Remove all tags with the given key from all future logs sent by this logger.
    ///
    /// Previous logs won't lose this tag if created prior to this call.
    ///
    /// - Parameter key: the key of the tag to remove
    func removeTag(withKey key: String)

    /// Adds the tag to all future logs sent by this logger.
    ///
    /// Tags must start with a letter and
    /// * may contain: alphanumerics, underscores, minuses, colons, periods and slashes;
    /// * other special characters are converted to underscores;
    /// * must be lowercase
    /// * and can be at most 200 characters long (tags exceeding this limit will be truncated to first 200 characters).
    ///
    /// See also: [Defining Tags](https://docs.datadoghq.com/tagging/#defining-tags)
    ///
    /// - Parameter tag: value of the tag
    func add(tag: String)

    /// Removes the tag from all future logs sent by this logger.
    ///
    /// Previous logs won't lose the this tag if created prior to this call.
    ///
    /// - Parameter tag: the value of the tag to remove
    func remove(tag: String)
}

public extension LoggerProtocol {
    /// Sends a DEBUG log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func debug(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .debug, message: message, error: error, attributes: attributes)
    }

    /// Sends an INFO log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func info(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .info, message: message, error: error, attributes: attributes)
    }

    /// Sends a NOTICE log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func notice(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .notice, message: message, error: error, attributes: attributes)
    }

    /// Sends a WARN log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func warn(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .warn, message: message, error: error, attributes: attributes)
    }

    /// Sends an ERROR log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func error(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .error, message: message, error: error, attributes: attributes)
    }

    /// Sends a CRITICAL log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: the error information (optional)
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (only for this message).
    func critical(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .critical, message: message, error: error, attributes: attributes)
    }
}

/// Datadog logger.
public class Logger: LoggerProtocol {
    /// An internal shim to V2 Logger.
    /// Needed for backward compatibility of V1 `Logger` APIs.
    internal let v2Logger: LoggerProtocol

    init(v2Logger: LoggerProtocol) {
        self.v2Logger = v2Logger
    }

    // MARK: - LoggerProtocol

    public func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        v2Logger.log(level: level, message: message, error: error, attributes: attributes)
    }

    public func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?) {
        v2Logger.log(
            level: level,
            message: message,
             errorKind: errorKind,
             errorMessage: errorMessage,
             stackTrace: stackTrace,
             attributes: attributes
        )
    }

    public func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        v2Logger.addAttribute(forKey: key, value: value)
    }

    public func removeAttribute(forKey key: AttributeKey) {
        v2Logger.removeAttribute(forKey: key)
    }

    public func addTag(withKey key: String, value: String) {
        v2Logger.addTag(withKey: key, value: value)
    }

    public func removeTag(withKey key: String) {
        v2Logger.removeTag(withKey: key)
    }

    public func add(tag: String) {
        v2Logger.add(tag: tag)
    }

    public func remove(tag: String) {
        v2Logger.remove(tag: tag)
    }

    // MARK: - Logger.Builder

    /// Creates `Logger` builder.
    public static var builder: Builder {
        return Builder()
    }

    /// `Logger` builder.
    ///
    /// Usage:
    ///
    ///     Logger.builder
    ///            ... // customize using builder methods
    ///           .build()
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
        /// If enabled all the logs will be bundled with the `Global.sharedTracer.activeSpan` trace and
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

        /// Builds `Logger` object.
        public func build(in core: DatadogCoreProtocol = defaultDatadogCore) -> Logger {
            do {
                return Logger(v2Logger: try buildOrThrow(in: core))
            } catch {
                DD.logger.critical("Failed to build `Logger`.", error: error)
                return Logger(v2Logger: NOPLogger())
            }
        }

        private func buildOrThrow(in core: DatadogCoreProtocol) throws -> LoggerProtocol {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `Logger.builder.build()`."
                )
            }

            guard let loggingFeature = core.v1.feature(LoggingFeature.self) else {
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
                    loggerName: loggerName ?? loggingFeature.configuration.applicationBundleIdentifier,
                    sendNetworkInfo: sendNetworkInfo,
                    threshold: datadogReportingThreshold,
                    eventMapper: loggingFeature.configuration.logEventMapper,
                    sampler: loggingFeature.configuration.remoteLoggingSampler
                )

                return RemoteLogger(
                    core: core,
                    configuration: configuration,
                    dateProvider: loggingFeature.configuration.dateProvider,
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
                    dateProvider: loggingFeature.configuration.dateProvider,
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
}

/// Combines multiple loggers together into single `LoggerProtocol` interface.
internal struct CombinedLogger: LoggerProtocol {
    let combinedLoggers: [LoggerProtocol]

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        combinedLoggers.forEach { $0.log(level: level, message: message, error: error, attributes: attributes) }
    }

    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?) {
        combinedLoggers.forEach {
            $0.log(
                level: level,
                message: message,
                errorKind: errorKind,
                errorMessage: errorMessage,
                stackTrace: stackTrace,
                attributes: attributes
            )
        }
    }

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        combinedLoggers.forEach { $0.addAttribute(forKey: key, value: value) }
    }

    func removeAttribute(forKey key: AttributeKey) {
        combinedLoggers.forEach { $0.removeAttribute(forKey: key) }
    }

    func addTag(withKey key: String, value: String) {
        combinedLoggers.forEach { $0.addTag(withKey: key, value: value) }
    }

    func removeTag(withKey key: String) {
        combinedLoggers.forEach { $0.removeTag(withKey: key) }
    }

    func add(tag: String) {
        combinedLoggers.forEach { $0.add(tag: tag) }
    }

    func remove(tag: String) {
        combinedLoggers.forEach { $0.remove(tag: tag) }
    }
}

internal struct NOPLogger: LoggerProtocol {
    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {}
    func log(level: LogLevel, message: String, errorKind: String?, errorMessage: String?, stackTrace: String?, attributes: [String: Encodable]?) {}
    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {}
    func removeAttribute(forKey key: AttributeKey) {}
    func addTag(withKey key: String, value: String) {}
    func removeTag(withKey key: String) {}
    func add(tag: String) {}
    func remove(tag: String) {}
}
