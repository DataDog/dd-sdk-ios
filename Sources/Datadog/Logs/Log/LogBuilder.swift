import Foundation

/// Builds `Log` representation as it was received from the user (without sanitization).
internal struct LogBuilder {
    let appContext: AppContext
    /// Service name to write in log.
    let serviceName: String
    /// Logger name to write in log.
    let loggerName: String
    /// Current date to write in log.
    let dateProvider: DateProvider

    func createLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>) -> Log {
        let encodableAttributes = Dictionary(
            uniqueKeysWithValues: attributes.map { name, value in (name, EncodableValue(value)) }
        )

        return Log(
            date: dateProvider.currentDate(),
            status: logStatus(for: level),
            message: message,
            serviceName: serviceName,
            loggerName: loggerName,
            loggerVersion: getSDKVersion(),
            threadName: getCurrentThreadName(),
            applicationVersion: getApplicationVersion(),
            attributes: !encodableAttributes.isEmpty ? encodableAttributes : nil,
            tags: !tags.isEmpty ? Array(tags) : nil
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

    private func getCurrentThreadName() -> String {
        if let customName = Thread.current.name, !customName.isEmpty {
            return customName
        } else {
            return Thread.isMainThread ? "main" : "background"
        }
    }

    private func getSDKVersion() -> String {
        return sdkVersion
    }

    private func getApplicationVersion() -> String {
        if let shortVersion = appContext.bundleShortVersion {
            return shortVersion
        } else if let version = appContext.bundleVersion {
            return version
        } else {
            return ""
        }
    }
}
