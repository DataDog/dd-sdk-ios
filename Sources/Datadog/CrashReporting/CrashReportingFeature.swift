/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns componetns enabling Crash Reporting feature.
internal final class CrashReportingFeature {
    /// Single, shared instance of `CrashReportingFeature`.
    static var instance: CrashReportingFeature?

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

    /// An interface for accessing the `DDCrashReportingPlugin` from `DatadogCrashReporting`.
    let plugin: DDCrashReportingPluginType
    /// Integration enabling sending crash reports as Logs. `nil` if the Logging feature is disabled.
    let loggingIntegration: CrashReportingIntegration?
    /// Integration enabling sending crash reports as RUM Errors. `nil` if the RUM feature is disabled.
    let rumIntegration: CrashReportingIntegration?

    init(
        configuration: FeaturesConfiguration.CrashReporting,
        loggingIntegration: CrashReportingIntegration?,
        rumIntegration: CrashReportingIntegration?
    ) {
        self.plugin = configuration.crashReportingPlugin
        self.loggingIntegration = loggingIntegration
        self.rumIntegration = rumIntegration
    }

    func sendCrashReportIfFound() {
        let loggingIntegration = self.loggingIntegration
        let rumIntegration = self.rumIntegration

        plugin.readPendingCrashReport { crashReport in
            if let availableCrashReport = crashReport {
                if let enabledRUMIntegration = rumIntegration {
                    enabledRUMIntegration.send(crashReport: availableCrashReport)
                    return true
                } else if let enabledLoggingIntegration = loggingIntegration {
                    enabledLoggingIntegration.send(crashReport: availableCrashReport)
                    return true
                } else {
                    userLogger.warn(
                        """
                        Pending crash report was found, but it cannot be send as both Logging and RUM features
                        are disabled. Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
                        when initializind Datadog SDK.
                        """
                    )
                    return false
                }
            }
            return false
        }
    }
}
