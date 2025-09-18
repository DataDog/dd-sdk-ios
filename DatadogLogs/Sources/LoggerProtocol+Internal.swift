/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Internal Logger for Cross-Platform access.
public protocol InternalLoggerProtocol {
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
    ///                 the same key already exist in this logger, it will be overridden (only for this message).
    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?
    )

    /// Logs a critical entry then call completion.
    ///
    /// This method is meant for non-native or cross platform frameworks (such as KMP) to send error information
    /// synchronously.
    ///
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to infer error details.
    ///   - message: the message to be logged
    ///   - attributes: a dictionary of attributes (optional) to add for this message. If an attribute with
    ///                 the same key already exist in this logger, it will be overridden (only for this message).
    ///   - completionHandler: A completion closure called when reporting the log is completed.
    func critical(
        message: String,
        error: Error?,
        attributes: [String: Encodable]?,
        completionHandler: @escaping CompletionHandler
    )
}

private struct NOPInternalLogger: InternalLoggerProtocol {
    func log(
        level: LogLevel,
        message: String,
        errorKind: String?,
        errorMessage: String?,
        stackTrace: String?,
        attributes: [String: Encodable]?
    ) { }

    func critical(
        message: String,
        error: Error?,
        attributes: [String: Encodable]?,
        completionHandler: @escaping CompletionHandler
    ) { completionHandler() }
}

/// Extends `LoggerProtocol` with additional methods designed for Datadog cross-platform SDKs.
extension LoggerProtocol {
    /// Grants access to an internal interface utilized only by Datadog cross-platform SDKs.
    /// **It is not meant for public use** and it might change without prior notice.
    public var _internal: InternalLoggerProtocol {
        self as? InternalLoggerProtocol ?? NOPInternalLogger()
    }
}
