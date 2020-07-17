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
}

/// A `String` value naming the attribute.
///
/// Dot syntax can be used to nest objects:
///
///     logger.addAttribute(forKey: "person.name", value: "Adam")
///     logger.addAttribute(forKey: "person.age", value: 32)
///
///     // When seen in Datadog console:
///     {
///         person: {
///             name: "Adam"
///             age: 32
///         }
///     }
///
/// - Important
/// Values can be nested up to 10 levels deep. Keys using more than 10 levels will be sanitized by SDK.
///
public typealias AttributeKey = String

/// Any `Ecodable` value of the attribute (`String`, `Int`, `Bool`, `Date` etc.).
///
/// Custom `Encodable` types are supported as well with nested encoding containers:
///
///     struct Person: Codable {
///         let name: String
///         let age: Int
///         let address: Address
///     }
///
///     struct Address: Codable {
///         let city: String
///         let street: String
///     }
///
///     let address = Address(city: "Paris", street: "Champs Elysees")
///     let person = Person(name: "Adam", age: 32, address: address)
///
///     // When seen in Datadog console:
///     {
///         person: {
///             name: "Adam"
///             age: 32
///             address: {
///                 city: "Paris",
///                 street: "Champs Elysees"
///             }
///         }
///     }
///
/// - Important
/// Attributes in Datadog console can be nested up to 10 levels deep. If number of nested attribute levels
/// defined as sum of key levels and value levels exceeds 10, the log will not be delivered.
///
public typealias AttributeValue = Encodable

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
    /// Writes `Log` objects to output.
    let logOutput: LogOutput
    /// Provides date for log creation.
    private let dateProvider: DateProvider
    /// Attributes associated with every log.
    private var loggerAttributes: [String: Encodable] = [:]
    /// Taggs associated with every log.
    private var loggerTags: Set<String> = []
    /// Queue ensuring thread-safety of the `Logger`. It synchronizes tags and attributes mutation.
    private let queue: DispatchQueue

    init(logOutput: LogOutput, dateProvider: DateProvider, identifier: String) {
        self.logOutput = logOutput
        self.dateProvider = dateProvider
        self.queue = DispatchQueue(
            label: "com.datadoghq.logger-\(identifier)",
            target: .global(qos: .userInteractive)
        )
    }

    // MARK: - Logging

    /// Sends a DEBUG log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func debug(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .debug, message: message, messageAttributes: attributes)
    }

    /// Sends an INFO log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func info(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .info, message: message, messageAttributes: attributes)
    }

    /// Sends a NOTICE log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func notice(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .notice, message: message, messageAttributes: attributes)
    }

    /// Sends a WARN log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func warn(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .warn, message: message, messageAttributes: attributes)
    }

    /// Sends an ERROR log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func error(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .error, message: message, messageAttributes: attributes)
    }

    /// Sends a CRITICAL log message.
    /// - Parameters:
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes to add for this message. If an attribute with
    /// the same key already exist in this logger, it will be overridden (just for this message).
    public func critical(_ message: String, attributes: [AttributeKey: AttributeValue]? = nil) {
        log(level: .critical, message: message, messageAttributes: attributes)
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

    private func log(level: LogLevel, message: String, messageAttributes: [String: Encodable]?) {
        let date = dateProvider.currentDate()
        let combinedAttributes = queue.sync {
            return self.loggerAttributes.merging(messageAttributes ?? [:]) { _, messageAttributeValue in
                return messageAttributeValue // use message attribute when the same key appears also in logger attributes
            }
        }
        let tags = queue.sync {
            return self.loggerTags
        }

        logOutput.writeLogWith(
            level: level,
            message: message,
            date: date,
            attributes: LogAttributes(userAttributes: combinedAttributes, internalAttributes: nil),
            tags: tags
        )
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
        internal var sendNetworkInfo: Bool = false
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
                    logOutput: NoOpLogOutput(),
                    dateProvider: SystemDateProvider(),
                    identifier: "no-op"
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

            return Logger(
                logOutput: resolveLogsOutput(for: loggingFeature),
                dateProvider: loggingFeature.dateProvider,
                identifier: resolveLoggerName(for: loggingFeature)
            )
        }

        private func resolveLogsOutput(for loggingFeature: LoggingFeature) -> LogOutput {
            let logBuilder = LogBuilder(
                applicationVersion: loggingFeature.configuration.applicationVersion,
                environment: loggingFeature.configuration.environment,
                serviceName: serviceName ?? loggingFeature.configuration.serviceName,
                loggerName: resolveLoggerName(for: loggingFeature),
                userInfoProvider: loggingFeature.userInfoProvider,
                networkConnectionInfoProvider: sendNetworkInfo ? loggingFeature.networkConnectionInfoProvider : nil,
                carrierInfoProvider: sendNetworkInfo ? loggingFeature.carrierInfoProvider : nil
            )

            switch (useFileOutput, useConsoleLogFormat) {
            case (true, let format?):
                return CombinedLogOutput(
                    combine: [
                        LogFileOutput(
                            logBuilder: logBuilder,
                            fileWriter: loggingFeature.storage.writer
                        ),
                        LogConsoleOutput(
                            logBuilder: logBuilder,
                            format: format,
                            timeZone: .current
                        )
                    ]
                )
            case (true, nil):
                return LogFileOutput(
                    logBuilder: logBuilder,
                    fileWriter: loggingFeature.storage.writer
                )
            case (false, let format?):
                return LogConsoleOutput(
                    logBuilder: logBuilder,
                    format: format,
                    timeZone: .current
                )
            case (false, nil):
                return NoOpLogOutput()
            }
        }

        private func resolveLoggerName(for loggingFeature: LoggingFeature) -> String {
            return loggerName ?? loggingFeature.configuration.applicationBundleIdentifier
        }
    }
}
