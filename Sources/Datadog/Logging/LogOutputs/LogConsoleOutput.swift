/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Formats logs printed to console.
internal protocol ConsoleLogFormatter {
    func format(log: Log) -> String
}

/// `LogOutput` which prints logs to console.
internal struct LogConsoleOutput: LogOutput {
    private let formatter: ConsoleLogFormatter
    private let printingFunction: (String) -> Void

    init(
        format: Logger.Builder.ConsoleLogFormat,
        timeZone: TimeZone,
        printingFunction: @escaping (String) -> Void = { consolePrint($0) }
    ) {
        switch format {
        case .short:
            self.formatter = ShortLogFormatter(timeZone: timeZone)
        case .shortWith(let prefix):
            self.formatter = ShortLogFormatter(timeZone: timeZone, prefix: prefix)
        case .json:
            self.formatter = JSONLogFormatter()
        case .jsonWith(let prefix):
            self.formatter = JSONLogFormatter(prefix: prefix)
        }
        self.printingFunction = printingFunction
    }

    func write(log: Log) {
        printingFunction(formatter.format(log: log))
    }
}

// MARK: - Formatters

/// Formats log as JSON string.
private struct JSONLogFormatter: ConsoleLogFormatter {
    private let encoder: JSONEncoder
    private let prefix: String

    init(prefix: String = "") {
        let encoder = JSONEncoder.default()
        encoder.outputFormatting = .prettyPrinted
        self.encoder = encoder
        self.prefix = prefix
    }

    func format(log: Log) -> String {
        do {
            let logJSON = String(data: try encoder.encode(log), encoding: .utf8) ?? ""
            return prefix + logJSON
        } catch {
            return "\(error)"
        }
    }
}

/// Formats log as custom short string.
private struct ShortLogFormatter: ConsoleLogFormatter {
    private let timeFormatter: DateFormatterType
    private let prefix: String

    init(timeZone: TimeZone, prefix: String = "") {
        self.timeFormatter = presentationDateFormatter(withTimeZone: timeZone)
        self.prefix = prefix
    }

    func format(log: Log) -> String {
        let time = timeFormatter.string(from: log.date)
        let status = log.status.rawValue.uppercased()
        return "\(prefix)\(time) [\(status)] \(log.message)"
    }
}
