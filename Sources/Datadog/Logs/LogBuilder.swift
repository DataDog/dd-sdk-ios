import Foundation

/// Representation of log.
internal struct Log: Encodable {
    enum Status: String, Encodable {
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
    let attributes: [String: EncodableValue]?

    // MARK: - Log encoding

    private enum CodingKeys: String, CodingKey {
        case date
        case status
        case message
        case service
    }

    private struct CustomCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(status, forKey: .status)
        try container.encode(message, forKey: .message)
        try container.encode(service, forKey: .service)

        if let attributes = attributes {
            var attributesContainer = encoder.container(keyedBy: CustomCodingKey.self)
            try attributes.forEach { try attributesContainer.encode($0.value, forKey: CustomCodingKey($0.key)) }
        }
    }
}

/// Builds `Log` objects.
internal struct LogBuilder {
    /// Service name to write in log.
    let serviceName: String
    /// Current date to write in log.
    let dateProvider: DateProvider

    func createLogWith(
        level: LogLevel,
        message: String,
        attributes: [String: EncodableValue]
    ) -> Log {
        return Log(
            date: dateProvider.currentDate(),
            status: Log.Status(for: level),
            message: message,
            service: serviceName,
            attributes: !attributes.isEmpty ? attributes : nil
        )
    }
}
