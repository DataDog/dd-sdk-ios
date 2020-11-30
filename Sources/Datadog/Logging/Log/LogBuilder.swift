/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `Log` representation (for later serialization) from data received from user.
internal struct LogBuilder {
    /// Application version to write in log.
    let applicationVersion: String
    /// Environment to write in log.
    let environment: String
    /// Service name to write in log.
    let serviceName: String
    /// Logger name to write in log.
    let loggerName: String
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider
    /// Shared network connection info provider (or `nil` if disabled for given logger).
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType?
    /// Shared mobile carrier info provider (or `nil` if disabled for given logger).
    let carrierInfoProvider: CarrierInfoProviderType?
    /// Adjusts log's time (device time) to server time.
    let dateCorrection: NTPDateCorrectionType?

    func createLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) -> Log {
        let dateInServerTime = dateCorrection?.toServerDate(deviceDate: date)
        return Log(
            date: dateInServerTime ?? date,
            status: logStatus(for: level),
            message: message,
            serviceName: serviceName,
            environment: environment,
            loggerName: loggerName,
            loggerVersion: sdkVersion,
            threadName: getCurrentThreadName(),
            applicationVersion: applicationVersion,
            userInfo: userInfoProvider.value,
            networkConnectionInfo: networkConnectionInfoProvider?.current,
            mobileCarrierInfo: carrierInfoProvider?.current,
            attributes: attributes,
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
}
