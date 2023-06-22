/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Datadog logger.
public class DatadogLogger: Logger {
    internal let logger: Logger

    internal init(_ logger: Logger) {
        self.logger = logger
    }

    // MARK: - LoggerProtocol

    public func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        logger.log(level: level, message: message, error: error, attributes: attributes)
    }

    public func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?) {
            logger.log(
            level: level,
            message: message,
             errorKind: errorKind,
             errorMessage: errorMessage,
             stackTrace: stackTrace,
             attributes: attributes
        )
    }

    public func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        logger.addAttribute(forKey: key, value: value)
    }

    public func removeAttribute(forKey key: AttributeKey) {
        logger.removeAttribute(forKey: key)
    }

    public func addTag(withKey key: String, value: String) {
        logger.addTag(withKey: key, value: value)
    }

    public func removeTag(withKey key: String) {
        logger.removeTag(withKey: key)
    }

    public func add(tag: String) {
        logger.add(tag: tag)
    }

    public func remove(tag: String) {
        logger.remove(tag: tag)
    }

    // MARK: - Builder

    /// Creates a `DatadogLogger` builder.
    public static var builder: Builder { Builder() }
}
