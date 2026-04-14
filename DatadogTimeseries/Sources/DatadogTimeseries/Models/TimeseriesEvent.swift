import Foundation

struct TimeseriesEvent: Codable {
    let dd: DD
    let application: Application
    let date: Int64
    let session: Session
    let source: String
    let type: String
    let service: String?
    let version: String?
    let timeseries: Timeseries

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

    struct DD: Codable {
        let formatVersion: Int

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    struct Application: Codable {
        let id: String
    }

    struct Session: Codable {
        let id: String
        let type: String
    }

    struct Timeseries: Codable {
        let id: String
        let name: TimeseriesName
        let start: Int64
        let end: Int64
        let data: [DataPoint]
    }

    struct DataPoint: Codable {
        let timestamp: Int64
        let dataPointValue: Double

        enum CodingKeys: String, CodingKey {
            case timestamp
            case dataPointValue = "data_point_value"
        }
    }
}
