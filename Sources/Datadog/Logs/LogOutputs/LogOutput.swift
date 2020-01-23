import Foundation

/// Type writting logs to some destination.
internal protocol LogOutput {
    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>)
}
