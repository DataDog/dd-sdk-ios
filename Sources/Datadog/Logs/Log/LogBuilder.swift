/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `Log` representation as it was received from the user (without sanitization).
internal struct LogBuilder {
    /// App information context.
    let appContext: AppContext
    /// Service name to write in log.
    let serviceName: String
    /// Logger name to write in log.
    let loggerName: String
    /// Current date to write in log.
    let dateProvider: DateProvider
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider
    /// Shared network connection info provider (or `nil` if disabled for given logger).
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType?
    /// Shared mobile carrier info provider (or `nil` if disabled for given logger).
    let carrierInfoProvider: CarrierInfoProviderType?

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
            loggerVersion: sdkVersion,
            threadName: getCurrentThreadName(),
            applicationVersion: getApplicationVersion(),
            userInfo: userInfoProvider.value,
            networkConnectionInfo: networkConnectionInfoProvider?.current,
            mobileCarrierInfo: carrierInfoProvider?.current,
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
