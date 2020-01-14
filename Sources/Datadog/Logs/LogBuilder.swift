import Foundation

/// Representation of log.
internal struct Log: Codable, Equatable {
    enum Status: String, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case warn = "WARN"
        case error = "ERROR"
        case critical = "CRITICAL"

        init(for logLevel: LogLevel) {
            switch logLevel {
            case .debug:    self = .debug
            case .info:     self = .info
            case .notice:   self = .notice
            case .warn:     self = .warn
            case .error:    self = .error
            case .critical: self = .critical
            }
        }
    }

    let date: Date
    let status: Status
    let message: String
    let service: String
}

/// Builds `Log` objects.
internal struct LogBuilder {
    /// Service name to write in log.
    let serviceName: String
    /// Current date to write in log.
    let dateProvider: DateProvider

    func createLogWith(level: LogLevel, message: String) -> Log {
        return Log(
            date: dateProvider.currentDate(),
            status: Log.Status(for: level),
            message: message,
            service: serviceName
        )
    }
}
