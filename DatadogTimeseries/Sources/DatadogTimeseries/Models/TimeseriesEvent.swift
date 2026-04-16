import Foundation

public struct TimeseriesEvent: Codable {
    public let dd: DD
    public let application: Application
    public let date: Int64
    public let session: Session
    public let source: String
    public let type: String
    public let service: String?
    public let version: String?
    public let timeseries: Timeseries

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application
        case date
        case session
        case source
        case type
        case service
        case version
        case timeseries
    }

    public struct DD: Codable {
        public let formatVersion: Int

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    public struct Application: Codable {
        public let id: String
    }

    public struct Session: Codable {
        public let id: String
        public let type: String
    }

    public struct Timeseries: Codable {
        public let id: String
        public let name: TimeseriesName
        public let start: Int64
        public let end: Int64
        public let data: [DataPoint]
    }

    public struct DataPoint: Codable {
        public let timestamp: Int64
        public let dataPointValue: Double

        enum CodingKeys: String, CodingKey {
            case timestamp
            case dataPointValue = "data_point_value"
        }
    }
}
