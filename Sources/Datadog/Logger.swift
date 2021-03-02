/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

    // MARK: - `LogLevel` <> `Log.Status` conversion

    internal var asLogStatus: Log.Status {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }

    internal init(from logStatus: Log.Status) {
        switch logStatus {
        case .debug:    self = .debug
        case .info:     self = .info
        case .notice:   self = .notice
        case .warn:     self = .warn
        case .error:    self = .error
        case .critical: self = .critical
        }
    }
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

public class Logger {
    /// Builds the `Log` from user input; `nil` for no-op logger.
    internal let logBuilder: LogBuilder?
    /// Writes the `Log` to file; `nil` for no-op logger.
    internal let logOutput: LogOutput?
    /// Provides date for log creation.
    private let dateProvider: DateProvider
    /// Attributes associated with every log.
    private var loggerAttributes: [String: Encodable] = [:]
    /// Taggs associated with every log.
    private var loggerTags: Set<String> = []
    /// Queue ensuring thread-safety of the `Logger`. It synchronizes tags and attributes mutation.
    private let queue: DispatchQueue
    /// Integration with RUM Context. `nil` if disabled for this Logger or if the RUM feature disabled.
    internal let rumContextIntegration: LoggingWithRUMContextIntegration?
    /// Integration with Tracing. `nil` if disabled for this Logger or if the Tracing feature disabled.
    internal let activeSpanIntegration: LoggingWithActiveSpanIntegration?
    /// Integration with Span context injected by environment.
    internal let environmentSpanIntegration = LoggingWithEnvironmentSpanIntegration()

    init(
        logBuilder: LogBuilder?,
        logOutput: LogOutput?,
        dateProvider: DateProvider,
        identifier: String,
        rumContextIntegration: LoggingWithRUMContextIntegration?,
        activeSpanIntegration: LoggingWithActiveSpanIntegration?
    ) {
        self.logBuilder = logBuilder
        self.logOutput = logOutput
        self.dateProvider = dateProvider
        self.queue = DispatchQueue(
            label: "com.datadoghq.logger-\(identifier)",
            target: .global(qos: .userInteractive)
        )
        self.rumContextIntegration = rumContextIntegration
        self.activeSpanIntegration = activeSpanIntegration
    }

    // MARK: - Logging

    /// Sends a DEBUG log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func debug(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .debug, message: message, error: error, messageAttributes: attributes)
    }

    /// Sends an INFO log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func info(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .info, message: message, error: error, messageAttributes: attributes)
    }

    /// Sends a NOTICE log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func notice(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .notice, message: message, error: error, messageAttributes: attributes)
    }

    /// Sends a WARN log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func warn(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .warn, message: message, error: error, messageAttributes: attributes)
    }

    /// Sends an ERROR log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func error(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .error, message: message, error: error, messageAttributes: attributes)
    }

    /// Sends a CRITICAL log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - error: `Error` instance to be logged with its properties
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func critical(_ message: String, error: Error? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .critical, message: message, error: error, messageAttributes: attributes)
    }

    // MARK: - Attributes

    /// Adds a custom attribute to all future logs sent by this logger.
    /// - Parameters:
    ///   - key: key for this attribute. See `AttributeKey` documentation for information about
    ///   nesting attribute values using dot `.` syntax.
    ///   - value: any value that conforms to `Encodable`. See `AttributeValue` documentation
    ///   for information about nested encoding containers limitation.
    public func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        queue.async {
            self.loggerAttributes[key] = value
        }
    }

    /// Removes the custom attribute from all future logs sent by this logger.
    /// Previous logs won't lose this attribute if they were created prior to this call.
    /// - Parameter key: key for the attribute that will be removed.
    public func removeAttribute(forKey key: AttributeKey) {
        queue.async {
            self.loggerAttributes.removeValue(forKey: key)
        }
    }

    // MARK: - Tags

    /// Adds a tag to all future logs sent by this logger.
    /// The tag will be in the format `key:value`.
    ///
    /// Tags must start with a letter and after that may contain the following characters:
    /// Alphanumerics, Underscores, Minuses, Colons, Periods, Slashes. Other special characters
    /// are converted to underscores.
    /// Tags must be lowercase, and can be at most 200 characters. If the tag is
    /// longer, only the first 200 characters will be used.
    ///
    /// # Reference
    /// [Defining Tags](https://docs.datadoghq.com/tagging/#defining-tags)
    ///
    /// - Parameter key: key for the tag
    /// - Parameter value: value of the tag
    public func addTag(withKey key: String, value: String) {
        queue.async {
            let prefix = "\(key):"
            self.loggerTags.insert("\(prefix)\(value)")
        }
    }

    /// Remove all tags with the given key from all future logs sent by this logger.
    /// Previous logs won't lose this tag if they were created prior to this call.
    ///
    /// - Parameter key: key of the tag to remove
    public func removeTag(withKey key: String) {
        queue.async {
            let prefix = "\(key):"
            self.loggerTags = self.loggerTags.filter { !$0.hasPrefix(prefix) }
        }
    }

    /// Adds a tag to all future logs sent by this logger.
    ///
    /// Tags must start with a letter and after that may contain the following characters:
    /// Alphanumerics, Underscores, Minuses, Colons, Periods, Slashes. Other special characters
    /// are converted to underscores.
    /// Tags must be lowercase, and can be at most 200 characters. If the tag is
    /// longer, only the first 200 characters will be used.
    ///
    /// # Reference
    /// [Defining Tags](https://docs.datadoghq.com/tagging/#defining-tags)
    ///
    /// - Parameter tag: value of the tag
    public func add(tag: String) {
        queue.async {
            self.loggerTags.insert(tag)
        }
    }

    /// Removes a tag from all future logs sent by this logger.
    /// Previous logs won't lose the this tag if they were created prior to this call.
    ///
    /// - Parameter tag: value of the tag to remove
    public func remove(tag: String) {
        queue.async {
            self.loggerTags.remove(tag)
        }
    }

    // MARK: - Private

    private func log(level: LogLevel, message: String, error: Error?, messageAttributes: [String: Encodable]?) {
        guard let logBuilder = logBuilder, let logOutput = logOutput else {
            return // ignore, as the `Logger` is no-op
        }

        var combinedUserAttributes = messageAttributes ?? [:]
        combinedUserAttributes = queue.sync {
            return self.loggerAttributes.merging(combinedUserAttributes) { _, userAttributeValue in
                return userAttributeValue // use message attribute when the same key appears also in logger attributes
            }
        }

        var combinedInternalAttributes: [String: Encodable] = [:]
        if let rumContextAttributes = rumContextIntegration?.currentRUMContextAttributes {
            combinedInternalAttributes.merge(rumContextAttributes) { $1 }
        }
        if let activeSpanAttributes = activeSpanIntegration?.activeSpanAttributes {
            combinedInternalAttributes.merge(activeSpanAttributes) { $1 }
        } else if let environmentSpanAttributes = environmentSpanIntegration.environmentSpanAttributes {
            combinedInternalAttributes.merge(environmentSpanAttributes) { $1 }
        }

        let tags = queue.sync {
            return self.loggerTags
        }

        let log = logBuilder.createLogWith(
            level: level,
            message: message,
            error: error.flatMap { DDError(error: $0) },
            date: dateProvider.currentDate(),
            attributes: LogAttributes(
                userAttributes: combinedUserAttributes,
                internalAttributes: combinedInternalAttributes
            ),
            tags: tags
        )

        logOutput.write(log: log)
    }

    // MARK: - Logger.Builder

    /// Creates logger builder.
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
        internal var serviceName: String?
        internal var loggerName: String?
        internal var sendNetworkInfo = false
        internal var bundleWithRUM = true
        internal var bundleWithTrace = true
        internal var useFileOutput = true
        internal var useConsoleLogFormat: ConsoleLogFormat?

        /// Sets the service name that will appear in logs.
        /// - Parameter serviceName: the service name  (default value is set to application bundle identifier)
        public func set(serviceName: String) -> Builder {
            self.serviceName = serviceName
            return self
        }

        /// Sets the logger name that will appear in logs.
        /// - Parameter loggerName: the logger custom name (default value is set to main bundle identifier)
        public func set(loggerName: String) -> Builder {
            self.loggerName = loggerName
            return self
        }

        /// Enriches logs with network connection info.
        /// This means: reachability status, connection type, mobile carrier name and many more will be added to each log.
        /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
        /// - Parameter enabled: `false` by default
        public func sendNetworkInfo(_ enabled: Bool) -> Builder {
            sendNetworkInfo = enabled
            return self
        }

        /// Enables the logs integration with RUM.
        /// If enabled all the logs will be enriched with the current RUM View information and
        /// it will be possible to see all the logs sent during a specific View lifespan in the RUM Explorer.
        /// - Parameter enabled: `true` by default
        public func bundleWithRUM(_ enabled: Bool) -> Builder {
            bundleWithRUM = enabled
            return self
        }

        /// Enables the logs integration with active span API from Tracing.
        /// If enabled all the logs will be bundled with the `Global.sharedTracer.activeSpan` trace and
        /// it will be possible to see all the logs sent during that specific trace.
        /// - Parameter enabled: `true` by default
        public func bundleWithTrace(_ enabled: Bool) -> Builder {
            bundleWithTrace = enabled
            return self
        }

        /// Enables logs to be sent to Datadog servers.
        /// Can be used to disable sending logs in development.
        /// See also: `printLogsToConsole(_:)`.
        /// - Parameter enabled: `true` by default
        public func sendLogsToDatadog(_ enabled: Bool) -> Builder {
            self.useFileOutput = enabled
            return self
        }

        /// Format to use when printing logs to console if `printLogsToConsole(_:)` is enabled.
        public enum ConsoleLogFormat {
            /// Prints short representation of log.
            case short
            /// Prints short representation of log with given prefix.
            case shortWith(prefix: String)
            /// Prints JSON representation of log.
            case json
            /// Prints JSON representation of log with given prefix.
            case jsonWith(prefix: String)
        }

        /// Enables  logs to be printed to debugger console.
        /// Can be used in development instead of sending logs to Datadog servers.
        /// See also: `sendLogsToDatadog(_:)`.
        /// - Parameters:
        ///   - enabled: `false` by default
        ///   - format: format to use when printing logs to console - either `.short` or `.json` (`.short` is default)
        public func printLogsToConsole(_ enabled: Bool, usingFormat format: ConsoleLogFormat = .short) -> Builder {
            useConsoleLogFormat = enabled ? format : nil
            return self
        }

        /// Builds `Logger` object.
        public func build() -> Logger {
            do {
                return try buildOrThrow()
            } catch {
                consolePrint("\(error)")
                return Logger(
                    logBuilder: nil,
                    logOutput: nil,
                    dateProvider: SystemDateProvider(),
                    identifier: "no-op",
                    rumContextIntegration: nil,
                    activeSpanIntegration: nil
                )
            }
        }

        private func buildOrThrow() throws -> Logger {
            guard let loggingFeature = LoggingFeature.instance else {
                throw ProgrammerError(
                    description: Datadog.instance == nil
                        ? "`Datadog.initialize()` must be called prior to `Logger.builder.build()`."
                        : "`Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
                )
            }

            let (logBuilder, logOutput) = resolveLogBuilderAndOutput(for: loggingFeature) ?? (nil, nil)

            return Logger(
                logBuilder: logBuilder,
                logOutput: logOutput,
                dateProvider: loggingFeature.dateProvider,
                identifier: resolveLoggerName(for: loggingFeature),
                rumContextIntegration: (RUMFeature.isEnabled && bundleWithRUM) ? LoggingWithRUMContextIntegration() : nil,
                activeSpanIntegration: (TracingFeature.isEnabled && bundleWithTrace) ? LoggingWithActiveSpanIntegration() : nil
            )
        }

        private func resolveLogBuilderAndOutput(for loggingFeature: LoggingFeature) -> (LogBuilder, LogOutput)? {
            let logBuilder = LogBuilder(
                applicationVersion: loggingFeature.configuration.common.applicationVersion,
                environment: loggingFeature.configuration.common.environment,
                serviceName: serviceName ?? loggingFeature.configuration.common.serviceName,
                loggerName: resolveLoggerName(for: loggingFeature),
                userInfoProvider: loggingFeature.userInfoProvider,
                networkConnectionInfoProvider: sendNetworkInfo ? loggingFeature.networkConnectionInfoProvider : nil,
                carrierInfoProvider: sendNetworkInfo ? loggingFeature.carrierInfoProvider : nil,
                dateCorrector: loggingFeature.dateCorrector
            )

            switch (useFileOutput, useConsoleLogFormat) {
            case (true, let format?):
                let logOutput = CombinedLogOutput(
                    combine: [
                        LogFileOutput(
                            fileWriter: loggingFeature.storage.writer,
                            rumErrorsIntegration: LoggingWithRUMErrorsIntegration()
                        ),
                        LogConsoleOutput(
                            format: format,
                            timeZone: .current
                        )
                    ]
                )
                return (logBuilder, logOutput)
            case (true, nil):
                let logOutput = LogFileOutput(
                    fileWriter: loggingFeature.storage.writer,
                    rumErrorsIntegration: LoggingWithRUMErrorsIntegration()
                )
                return (logBuilder, logOutput)
            case (false, let format?):
                let logOutput = LogConsoleOutput(
                    format: format,
                    timeZone: .current
                )
                return (logBuilder, logOutput)
            case (false, nil):
                return nil
            }
        }

        private func resolveLoggerName(for loggingFeature: LoggingFeature) -> String {
            return loggerName ?? loggingFeature.configuration.common.applicationBundleIdentifier
        }
    }
}
