import Foundation

/// Representation of log uploaded to server.
internal struct Log: Codable, Equatable {
    enum Status: String, Codable {
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
}
