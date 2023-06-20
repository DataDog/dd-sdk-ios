/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `Logger` printing logs to console.
internal final class ConsoleLogger: LoggerProtocol {
    struct Configuration {
        /// Time zone for rendering logs.
        let timeZone: TimeZone
        /// The format of rendering logs in console.
        let format: Logger.Configuration.ConsoleLogFormat
    }

    /// Date provider for logs.
    private let dateProvider: DateProvider
    /// Time formatter for rendering log's date in console.
    private let timeFormatter: DateFormatterType
    /// The prefix to use when rendering log.
    private let prefix: String
    /// The function used to render log.
    private let printFunction: (String) -> Void

    init(
        configuration: Configuration,
        dateProvider: DateProvider,
        printFunction: @escaping (String) -> Void
    ) {
        self.dateProvider = dateProvider
        self.timeFormatter = presentationDateFormatter(withTimeZone: configuration.timeZone)

        switch configuration.format {
        case .short:
            self.prefix = ""
        case .shortWith(let prefix):
            self.prefix = "\(prefix) "
        }

        self.printFunction = printFunction
    }

    // MARK: - Logging

    func log(level: LogLevel, message: String, error: Error?, attributes: [String: Encodable]?) {
        var errorString: String? = nil
        if let error = error {
            let ddError = DDError(error: error)
            errorString = buildErrorString(error: ddError)
        }

        internalLog(level: level, message: message, errorString: errorString)
    }

    func log(level: LogLevel, message: String, errorKind: String?, errorMessage: String?, stackTrace: String?, attributes: [String: Encodable]?) {
        var errorString: String? = nil
        if errorKind != nil || errorMessage != nil || stackTrace != nil {
            // Cross platform frameworks don't necessarilly send all values for errors. Send empty strings
            // for any values that are empty.
            let ddError = DDError(type: errorKind ?? "", message: errorMessage ?? "", stack: stackTrace ?? "")
            errorString = buildErrorString(error: ddError)
        }

        internalLog(level: level, message: message, errorString: errorString)
    }

    private func internalLog(level: LogLevel, message: String, errorString: String?) {
        let time = timeFormatter.string(from: dateProvider.now)
        let status = level.asLogStatus.rawValue.uppercased()

        var log = "\(self.prefix)\(time) [\(status)] \(message)"

        if let errorString = errorString {
            log += "\n\nError details:\n\(errorString)"
        }

        printFunction(log)
    }

    private func buildErrorString(error: DDError) -> String {
        return """
        → type: \(error.type)
        → message: \(error.message)
        → stack: \(error.stack)
        """
    }

    // MARK: - Attributes (no-op for this logger)

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {}
    func removeAttribute(forKey key: AttributeKey) {}

    // MARK: - Tags (no-op for this logger)

    func addTag(withKey key: String, value: String) {}
    func removeTag(withKey key: String) {}
    func add(tag: String) {}
    func remove(tag: String) {}
}
