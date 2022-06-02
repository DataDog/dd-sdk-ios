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

    internal var asLogStatus: LogEvent.Status {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }

    internal init?(from logStatus: LogEvent.Status) {
        switch logStatus {
        case .debug:    self = .debug
        case .info:     self = .info
        case .notice:   self = .notice
        case .warn:     self = .warn
        case .error:    self = .error
        case .critical: self = .critical
        case .emergency: return nil // unavailable in public `LogLevel` API.
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
    internal typealias LogEventValidation = (LogEvent) -> Bool

    internal let core: DatadogCoreProtocol
    /// Attributes associated with every log.
    private var loggerAttributes: [String: Encodable] = [:]
    /// Taggs associated with every log.
    private var loggerTags: Set<String> = []
    /// Queue ensuring thread-safety of the `Logger`. It synchronizes tags and attributes mutation.
    private let queue: DispatchQueue

    internal let serviceName: String?
    internal let loggerName: String?
    internal let sendNetworkInfo: Bool
    internal let useCoreOutput: Bool
    internal let validate: LogEventValidation
    internal let additionalOutput: LogOutput?
    /// Log events mapper configured by the user, `nil` if not set.
    internal let logEventMapper: LogEventMapper?
    /// Integration with RUM Context. `nil` if disabled for this Logger or if the RUM feature disabled.
    internal let rumContextIntegration: LoggingWithRUMContextIntegration?
    /// Integration with Tracing. `nil` if disabled for this Logger or if the Tracing feature disabled.
    internal let activeSpanIntegration: LoggingWithActiveSpanIntegration?

    init(
        core: DatadogCoreProtocol,
        identifier: String,
        serviceName: String?,
        loggerName: String?,
        sendNetworkInfo: Bool,
        useCoreOutput: Bool,
        validation: LogEventValidation?,
        rumContextIntegration: LoggingWithRUMContextIntegration?,
        activeSpanIntegration: LoggingWithActiveSpanIntegration?,
        additionalOutput: LogOutput?,
        logEventMapper: LogEventMapper?
    ) {
        self.core = core
        self.queue = DispatchQueue(
            label: "com.datadoghq.logger-\(identifier)",
            target: .global(qos: .userInteractive)
        )
        self.serviceName = serviceName
        self.loggerName = loggerName
        self.sendNetworkInfo = sendNetworkInfo
        self.useCoreOutput = useCoreOutput
        self.validate = validation ?? { _ in true }
        self.additionalOutput = additionalOutput
        self.logEventMapper = logEventMapper
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
        }

        let tags = queue.sync {
            return self.loggerTags
        }

        core.v1.scope(for: LoggingFeature.self)?.execute { context, writer in
            let builder = LogEventBuilder(
                sdkVersion: context.sdkVersion,
                applicationVersion: context.version,
                environment: context.env,
                serviceName: self.serviceName ?? context.service,
                loggerName: self.loggerName ?? context.applicationBundleIdentifier,
                userInfoProvider: context.userInfoProvider,
                networkConnectionInfoProvider: self.sendNetworkInfo ? context.networkConnectionInfoProvider : nil,
                carrierInfoProvider: self.sendNetworkInfo ? context.carrierInfoProvider : nil,
                dateCorrector: context.dateCorrector,
                logEventMapper: self.logEventMapper
            )

            let event = builder.createLogWith(
                level: level,
                message: message,
                error: error.map { DDError(error: $0) },
                date: context.dateProvider.currentDate(),
                attributes: .init(
                    userAttributes: combinedUserAttributes,
                    internalAttributes: combinedInternalAttributes
                ),
                tags: tags
            )

            guard let log = event, self.validate(log) else {
                return
            }

            self.additionalOutput?.write(log: log)

            if self.useCoreOutput {
                writer.write(value: log)
            }
        }
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
        internal var useCoreOutput = true
        internal var consoleLogFormat: ConsoleLogFormat?

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
            self.useCoreOutput = enabled
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
            consoleLogFormat = enabled ? format : nil
            return self
        }

        /// Builds `Logger` object.
        public func build(in core: DatadogCoreProtocol = defaultDatadogCore) -> Logger {
            do {
                return try buildOrThrow(in: core)
            } catch {
                consolePrint("\(error)")
                return Logger(
                    core: NOOPDatadogCore(),
                    identifier: "no-op",
                    serviceName: nil,
                    loggerName: nil,
                    sendNetworkInfo: false,
                    useCoreOutput: false,
                    validation: nil,
                    rumContextIntegration: nil,
                    activeSpanIntegration: nil,
                    additionalOutput: nil,
                    logEventMapper: nil
                )
            }
        }

        private func buildOrThrow(in core: DatadogCoreProtocol) throws -> Logger {
            guard let context = core.v1.context else {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `Logger.builder.build()`."
                )
            }

            guard let loggingFeature = core.v1.feature(LoggingFeature.self) else {
                throw ProgrammerError(
                    description: "`Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
                )
            }

            // RUMM-2133 Note: strong feature coupling while migrating to v2.
            // In v2 active span will be provided in context from feature scope.
            let rumEnabled = core.v1.feature(RUMFeature.self) != nil
            let tracingEnabled = core.v1.feature(TracingFeature.self) != nil

            return Logger(
                core: core,
                identifier: loggerName ?? context.applicationBundleIdentifier,
                serviceName: serviceName,
                loggerName: loggerName,
                sendNetworkInfo: sendNetworkInfo,
                useCoreOutput: useCoreOutput,
                validation: nil,
                rumContextIntegration: (rumEnabled && bundleWithRUM) ? LoggingWithRUMContextIntegration() : nil,
                activeSpanIntegration: (tracingEnabled && bundleWithTrace) ? LoggingWithActiveSpanIntegration() : nil,
                additionalOutput: resolveOuput(),
                logEventMapper: loggingFeature.configuration.logEventMapper
            )
        }

        private func resolveOuput() -> LogOutput? {
            switch (useCoreOutput, consoleLogFormat) {
            case let (true, format?):
                return CombinedLogOutput(
                    combine: [
                        LogConsoleOutput(format: format, timeZone: .current),
                        LoggingWithRUMErrorsIntegration()
                    ]
                )
            case (true, nil):
                return LoggingWithRUMErrorsIntegration()
            case let (false, format?):
                return LogConsoleOutput(format: format, timeZone: .current)
            case (false, nil):
                return nil
            }
        }
    }
}
