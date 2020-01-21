import Foundation

/// Type writting logs to some destination.
internal protocol LogOutput {
    func writeLogWith(level: LogLevel, message: @autoclosure () -> String, attributes: [String: EncodableValue])
}
