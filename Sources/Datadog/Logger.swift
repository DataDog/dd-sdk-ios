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

//nested encoding containers limitation.

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

public class Logger {
    /// Writes `Log` objects to output.
    let logOutput: LogOutput
    /// Attributes associated with every log.
    private var loggerAttributes: [String: Encodable] = [:]

    init(logOutput: LogOutput) {
        self.logOutput = logOutput
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
        loggerAttributes[key] = value
    }

    /// Removes the custom attribute from all future logs sent by this logger.
    /// Previous logs won't lose this attribute if they were created prior to this call.
    /// - Parameter key: key for the attribute that will be removed.
    public func removeAttribute(forKey key: AttributeKey) {
        loggerAttributes.removeValue(forKey: key)
    }

    // MARK: - Private

    private func log(level: LogLevel, message: String, messageAttributes: [String: Encodable]?) {
        let combinedAttributes = loggerAttributes.merging(messageAttributes ?? [:]) { _, messageAttributeValue in
            return messageAttributeValue // use message attribute when the same key appears also in logger attributes
        }

        logOutput.writeLogWith(level: level, message: message, attributes: combinedAttributes)
    }

    // MARK: - Logger.Builder

    public static var builder: Builder {
        return Builder()
    }

    public class Builder {
        private var serviceName: String = "ios"
        private var useFileOutput = true
        private var useConsoleLogFormat: ConsoleLogFormat?

        /// Sets the service name that will appear in logs.
        /// - Parameter serviceName: the service name (default value is "ios")
        public func set(serviceName: String) -> Builder {
            self.serviceName = serviceName
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

        public func build() -> Logger {
            do { return try buildOrThrow()
            } catch {
                userLogger.critical("\(error)")
                fatalError("`Logger` cannot be built: \(error)") // crash
            }
        }

        internal func buildOrThrow() throws -> Logger {
            guard let datadog = Datadog.instance else {
                throw ProgrammerError(description: "`Datadog.initialize()` must be called prior to `Logger.builder.build()`.")
            }

            return Logger(logOutput: resolveLogsOutput(using: datadog))
        }

        private func resolveLogsOutput(using datadog: Datadog) -> LogOutput {
            let logBuilder = LogBuilder(
                serviceName: serviceName,
                dateProvider: datadog.dateProvider
            )

            switch (useFileOutput, useConsoleLogFormat) {
            case (true, let format?):
                return CombinedLogOutput(
                    combine: [
                        LogFileOutput(
                            logBuilder: logBuilder,
                            fileWriter: datadog.logsPersistenceStrategy.writer
                        ),
                        LogConsoleOutput(
                            logBuilder: logBuilder,
                            format: format
                        )
                    ]
                )
            case (true, nil):
                return LogFileOutput(
                    logBuilder: logBuilder,
                    fileWriter: datadog.logsPersistenceStrategy.writer
                )
            case (false, let format?):
                return LogConsoleOutput(
                    logBuilder: logBuilder,
                    format: format
                )
            case (false, nil):
                return NoOpLogOutput()
            }
        }
    }
}
