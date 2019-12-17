import Foundation

/// Representation of log uploaded to server.
struct Log: Codable, Equatable {
    let date: Date
    let status: String
    let message: String
    let service: String
}
