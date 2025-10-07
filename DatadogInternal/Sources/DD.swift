/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Core utilities for monitoring performance and execution of the SDK.
///
/// These are meant to be shared by all instances of the SDK and `DatadogCore`.
/// `DD` bundles static dependencies that must be available and functional right away,
/// so it is possible to monitor any phase of the SDK execution, including its initialization sequence.
public struct DD {
    /// The logger providing methods to print debug information and execution errors from Datadog SDK to user console.
    ///
    /// It is meant for debugging purposes when using the SDK, hence **it should log information useful and actionable
    /// to the SDK user**. Think of possible logs that we may want to receive from our users when asking them to enable
    /// SDK verbosity and send us their console log.
    ///
    /// The lock prevents race conditions when the logger is replaced
    /// during SDK initialization while being accessed from other threads.
    @ReadWriteLock
    public static var logger: CoreLogger = InternalLogger(
        dateProvider: SystemDateProvider(),
        timeZone: .current,
        printFunction: consolePrint,
        verbosityLevel: { .debug }
    )
}

#if canImport(OSLog)
import OSLog
#endif

/// Function printing `String` content to console.
public var consolePrint: @Sendable (String, CoreLoggerLevel) -> Void = { message, level in
    #if canImport(OSLog)
    if #available(iOS 14.0, tvOS 14.0, *) {
        switch level {
        case .debug: Logger.datadog.debug("\(message, privacy: .private)")
        case .warn: Logger.datadog.warning("\(message, privacy: .private)")
        case .error: Logger.datadog.critical("\(message, privacy: .private)")
        case .critical: Logger.datadog.fault("\(message, privacy: .private)")
        }
    } else {
        print(message)
    }
    #else
    print(message)
    #endif
}

#if canImport(OSLog)
@available(iOS 14.0, tvOS 14.0, *)
extension Logger {
    static let datadog = Logger(subsystem: "dd-sdk-ios", category: "DatadogInternal")
}
#endif
