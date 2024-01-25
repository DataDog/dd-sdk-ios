/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `CoreLogger` printing to debugger console.
public struct InternalLogger: CoreLogger {
    /// The prefix applied to all core logs.
    private static let prefix = "[DATADOG SDK] 🐶 → "

    /// The date provider for annotating core logs.
    private let dateProvider: DateProvider
    /// Formatter used to format the time accordingly for local device.
    private let dateFormatter: DateFormatterType
    /// The print function.
    private let printFunction: (String, CoreLoggerLevel) -> Void
    /// V1's verbosity level. Only logs above or equal to this level wil be printed.
    private let currentVerbosityLevel: () -> CoreLoggerLevel?

    public init(
        dateProvider: DateProvider,
        timeZone: TimeZone,
        printFunction: @escaping (String, CoreLoggerLevel) -> Void,
        verbosityLevel: @escaping () -> CoreLoggerLevel?
    ) {
        self.dateProvider = dateProvider
        self.dateFormatter = presentationDateFormatter(withTimeZone: timeZone)
        self.printFunction = printFunction
        self.currentVerbosityLevel = verbosityLevel
    }

    // MARK: - CoreLogger

    public func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?) {
        guard let verbosityLevel = currentVerbosityLevel(), level >= verbosityLevel else {
            return // if no `Datadog.verbosityLevel` is set or it is set above this level
        }

        print(message: message(), error: error, level: level)
    }

    // MARK: - Private

    private func print(message: @autoclosure () -> String, error: Error?, level: CoreLoggerLevel) {
        var log = buildMessageString(message: message(), emoji: level.emojiPrefix)

        if let error = error {
            log += "\n\nError details:\n\(buildErrorString(error: error))"
        }
        printFunction(log, level)
    }

    private func buildMessageString(message: @autoclosure () -> String, emoji: String) -> String {
        let prefix = InternalLogger.prefix
        let time = dateFormatter.string(from: dateProvider.now)

        if !emoji.isEmpty {
            return "\(prefix)\(time) \(emoji) \(message())"
        } else {
            return "\(prefix)\(time) \(message())"
        }
    }

    private func buildErrorString(error: Error) -> String {
        let dderror = DDError(error: error)
        return """
        → type: \(dderror.type)
        → message: \(dderror.message)
        → stack: \(dderror.stack)
        """
    }
}
