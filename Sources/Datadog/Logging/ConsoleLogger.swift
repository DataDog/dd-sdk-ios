/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Logger` printing logs to console.
internal final class ConsoleLogger: LoggerProtocol {
    struct Configuration {
        /// Time zone for rendering logs.
        let timeZone: TimeZone
        /// The format of rendering logs in console.
        let format: Logger.Builder.ConsoleLogFormat
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
        let time = timeFormatter.string(from: dateProvider.now)
        let status = level.asLogStatus.rawValue.uppercased()

        var log = "\(self.prefix)\(time) [\(status)] \(message)"

        if let error = error {
            log += "\n\nError details:\n\(buildErrorString(error: error))"
        }

        printFunction(log)
    }

    private func buildErrorString(error: Error) -> String {
        let dderror = DDError(error: error)
        return """
        → type: \(dderror.type)
        → message: \(dderror.message)
        → stack: \(dderror.stack)
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
