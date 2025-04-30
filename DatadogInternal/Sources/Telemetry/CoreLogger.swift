/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum CoreLoggerLevel: Int, Comparable, CaseIterable {
    /// Least severe level, meant to self-diagnose possible issues with the SDK.
    /// It **should be used to log all events which might be important for us in diagnosing the SDK**
    /// in user apps (e.g.: printing the SDK version or important aspects of configuration).
    ///
    /// No emoji prefix should be added by the logger when showing this log to the user.
    case debug

    /// Level indicating **an user error when using the SDK**. It should be used for
    /// logging errors that are caused by user fault (e.g. wrong configuration).
    ///
    /// The "⚠️" emoji prefix should be added by the logger when showing this log to the user.
    case warn

    /// Level indicating **an error in the SDK**. It shuld be only used for logging errors
    /// which are not caused by the user (e.g. SDK logic fault).
    ///
    /// The "🔥" emoji prefix should be added by the logger when showing this log to the user.
    case error

    /// Most severe level for logging errors which **makes some part of the SDK unfunctional**.
    /// It can be used to indicate either fatal SDK errors or user faults.
    ///
    /// The "⛔️" emoji prefix should be added by the logger when showing this log to the user.
    case critical

    var emojiPrefix: String {
        switch self {
        case .debug:    return ""
        case .warn:     return "⚠️"
        case .error:    return "🔥"
        case .critical: return "⛔️"
        }
    }

    public static func < (lhs: CoreLoggerLevel, rhs: CoreLoggerLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@objc
public enum DDSDKVerbosityLevel: Int {
    case none
    case debug
    case warn
    case error
    case critical
}

/// The `CoreLogger` protocol defines methods to log debug information and execution errors from Datadog SDK to user console.
///
/// It is meant for debugging purposes when using the SDK, hence **it should log information useful and actionable
/// to the SDK user**. Think of possible logs that we may want to receive from our users when asking them to enable
/// SDK verbosity and send us their console log.
public protocol CoreLogger {
    /// Log the message and error using given severity level.
    ///
    /// - Parameters:
    ///   - level: the severity level
    ///   - message: the message to be shown
    ///   - error: eventual `Error` which will be showed in a nice format
    func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?)
}

extension CoreLogger {
    /// Print debug message which is meant to self-diagnose possible issues with the SDK.
    /// It should be used to log all events which might be important for us in diagnosing the SDK
    /// in user apps (e.g.: printing the SDK version or important aspects of configuration).
    ///
    /// No emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    public func debug(_ message: @autoclosure () -> String, error: Error? = nil) {
        log(.debug, message: message(), error: error)
    }

    /// Print error message which indicates **an user error when using the SDK**. It should be used for
    /// indicating errors that are caused by user fault (e.g. wrong configuration).
    ///
    /// The "⚠️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    public func warn(_ message: @autoclosure () -> String, error: Error? = nil) {
        log(.warn, message: message(), error: error)
    }

    /// Print error message which indicates **an error in the SDK**. It shuld be only used for errors
    /// which are not caused by the user (e.g. SDK user fault).
    ///
    /// The "🔥" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    public func error(_ message: @autoclosure () -> String, error: Error? = nil) {
        log(.error, message: message(), error: error)
    }

    /// Print error message which indicates an error which **makes some part of the SDK unfunctional**.
    /// It can be used to indicate either fatal SDK errors or user fault.
    ///
    /// The "⛔️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    public func critical(_ message: @autoclosure () -> String, error: Error? = nil) {
        log(.critical, message: message(), error: error)
    }
}
