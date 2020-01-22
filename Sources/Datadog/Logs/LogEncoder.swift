import Foundation

/// `Encodable` representation of log.
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
