import Foundation

/// Builds `Log` representation as it was received from the user (without sanitization).
internal struct LogBuilder {
    /// Service name to write in log.
    let serviceName: String
    /// Current date to write in log.
    let dateProvider: DateProvider

    func createLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) -> Log {
        let encodableAttributes = Dictionary(
            uniqueKeysWithValues: attributes.map { name, value in (name, EncodableValue(value)) }
        )

        return Log(
            date: dateProvider.currentDate(),
            status: logStatus(for: level),
            message: message,
            service: serviceName,
            attributes: !encodableAttributes.isEmpty ? encodableAttributes : nil
        )
    }

    private func logStatus(for level: LogLevel) -> Log.Status {
        switch level {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }
}
