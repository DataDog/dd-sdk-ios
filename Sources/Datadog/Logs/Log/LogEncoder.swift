import Foundation

/// `Encodable` representation of log. Sanitizes the log before encoding.
internal struct Log: Encodable {
    enum Status: String, Encodable {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case warn = "WARN"
        case error = "ERROR"
        case critical = "CRITICAL"
    }

    let date: Date
    let status: Status
    let message: String
    let service: String
    let attributes: [String: EncodableValue]?

    func encode(to encoder: Encoder) throws {
        let sanitizedLog = LogSanitizer().sanitize(log: self)
        try LogEncoder().encode(sanitizedLog, to: encoder)
    }
}

/// Encodes `Log` to given encoder.
internal struct LogEncoder {
    /// Coding keys for permanent `Log` attributes.
    private enum StaticCodingKeys: String, CodingKey {
        case date
        case status
        case message
        case service
    }

    /// Coding keys for dynamic `Log` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(_ log: Log, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(log.date, forKey: .date)
        try container.encode(log.status, forKey: .status)
        try container.encode(log.message, forKey: .message)
        try container.encode(log.service, forKey: .service)

        if let attributes = log.attributes {
            var attributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            try attributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }
        }
    }
}
