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
    /// Time formatter used for `.short` output format.
    static func shortTimeFormatter(calendar: Calendar = .current, timeZone: TimeZone = .current) -> Formatter {
        guard #available(OSX 10.12, *) else {
            return iso8601DateFormatter()
        }

        let formatter = ISO8601DateFormatter.default()
        var options: ISO8601DateFormatter.Options = [.withFullTime]

        if #available(OSX 10.14, *) {
            options.insert(.withFractionalSeconds)
        }

        formatter.formatOptions = options
        return formatter
    }

    private let logBuilder: LogBuilder
    private let formatter: ConsoleLogFormatter
    private let printingFunction: (String) -> Void

    init(
        logBuilder: LogBuilder,
        format: Logger.Builder.ConsoleLogFormat,
        printingFunction: @escaping (String) -> Void = { consolePrint($0) },
        timeFormatter: Formatter = LogConsoleOutput.shortTimeFormatter()
    ) {
        switch format {
        case .short:
            self.formatter = ShortLogFormatter(timeFormatter: timeFormatter)
        case .shortWith(let prefix):
            self.formatter = ShortLogFormatter(timeFormatter: timeFormatter, prefix: prefix)
        case .json:
            self.formatter = JSONLogFormatter()
        case .jsonWith(let prefix):
            self.formatter = JSONLogFormatter(prefix: prefix)
        }
        self.logBuilder = logBuilder
        self.printingFunction = printingFunction
    }

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>) {
        let log = logBuilder.createLogWith(level: level, message: message, attributes: attributes, tags: tags)
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
    private let timeFormatter: Formatter
    private let prefix: String

    init(timeFormatter: Formatter, prefix: String = "") {
        self.timeFormatter = timeFormatter
        self.prefix = prefix
    }

    func format(log: Log) -> String {
        let time = timeFormatter.string(for: log.date)
        let status = log.status.rawValue.uppercased()
        return "\(prefix)\(time ?? "null") [\(status)] \(log.message)"
    }
}
