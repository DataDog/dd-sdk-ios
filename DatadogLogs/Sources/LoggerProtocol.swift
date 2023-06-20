/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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

/// Datadog Logger.
///
/// Usage:
///
///     import DatadogLogs
///
///     // Initialise the Logs module
///
///     // logger reference
///     var logger = Logger.create()
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
