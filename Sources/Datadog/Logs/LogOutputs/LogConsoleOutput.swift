import Foundation

/// Formats logs printed to console.
internal protocol ConsoleLogFormatter {
    func format(log: Log) -> String
}

/// `LogOutput` which prints logs to console.
internal struct LogConsoleOutput: LogOutput {
    /// Time formatter used for `.short` output format.
    static func shortTimeFormatter(calendar: Calendar = .current, timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private let logBuilder: LogBuilder
    private let formatter: ConsoleLogFormatter
    private let printingFunction: (String) -> Void

    init(
        logBuilder: LogBuilder,
        format: Logger.Builder.ConsoleLogFormat,
        printingFunction: @escaping (String) -> Void = { print($0) },
        timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
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

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) {
        let log = logBuilder.createLogWith(level: level, message: message, attributes: attributes)
        printingFunction(formatter.format(log: log))
    }
}

// MARK: - Formatters

/// Formats log as JSON string.
private struct JSONLogFormatter: ConsoleLogFormatter {
    private let encoder: JSONEncoder
    private let prefix: String

    init(prefix: String = "") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
    private let timeFormatter: DateFormatter
    private let prefix: String

    init(timeFormatter: DateFormatter, prefix: String = "") {
        self.timeFormatter = timeFormatter
        self.prefix = prefix
    }

    func format(log: Log) -> String {
        let time = timeFormatter.string(from: log.date)
        let status = log.status.rawValue.uppercased()
        return "\(prefix)\(time) [\(status)] \(log.message)"
    }
}
