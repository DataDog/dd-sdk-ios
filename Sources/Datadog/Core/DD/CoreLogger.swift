/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `CoreLogger` protocol defines methods to print debug information and execution errors from Datadog SDK to user console.
///
/// It is meant for debugging purposes when using the SDK, hence **it should log information useful and actionable
/// to the SDK user**. Think of possible logs that we may want to receive from our users when asking them to enable
/// SDK verbosity and send us their console log.
internal protocol CoreLogger {
    /// Print debug message which is meant to self-diagnose possible issues with the SDK.
    /// It should be used to log all events which might be important for us in diagnosing the SDK
    /// in user apps (e.g.: printing the SDK version or important aspects of configuration).
    ///
    /// No emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    func debug(_ message: @autoclosure () -> String, error: Error?)

    /// Print error message which indicates **an user error when using the SDK**. It should be used for
    /// indicating errors that are caused by user fault (e.g. wrong configuration).
    ///
    /// The "⚠️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    func warn(_ message: @autoclosure () -> String, error: Error?)

    /// Print error message which indicates **an error in the SDK**. It shuld be only used for errors
    /// which are not caused by the user (e.g. due to wrong configuration).
    ///
    /// The "🔥" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    func error(_ message: @autoclosure () -> String, error: Error?)

    /// Print error message which indicates an error which **makes some part of the SDK unfunctional**.
    /// It can be used to indicate either fatal SDK errors or user fault.
    ///
    /// The "⛔️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    ///   - error: eventual `Error` which will be printed in nice format
    func critical(_ message: @autoclosure () -> String, error: Error?)
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
    func debug(_ message: @autoclosure () -> String) {
        debug(message(), error: nil)
    }

    /// Print error message which indicates **an user error when using the SDK**. It should be used for
    /// indicating errors that are caused by user fault (e.g. wrong configuration).
    ///
    /// The "⚠️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    func warn(_ message: @autoclosure () -> String) {
        warn(message(), error: nil)
    }

    /// Print error message which indicates **an error in the SDK**. It shuld be only used for errors
    /// which are not caused by the user (e.g. due to wrong configuration).
    ///
    /// The "🔥" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    func error(_ message: @autoclosure () -> String) {
        error(message(), error: nil)
    }

    /// Print error message which indicates an error which **makes some part of the SDK unfunctional**.
    /// It can be used to indicate either fatal SDK errors or user fault.
    ///
    /// The "⛔️" emoji prefix is added by the logger when priting this log to the console.
    ///
    /// - Parameters:
    ///   - message: the message
    func critical(_ message: @autoclosure () -> String) {
        critical(message(), error: nil)
    }
}
