/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receives `LaunchReport` from CrashReporter and starts the Watchdog Termination Monitor.
internal struct LaunchReportReceiver: FeatureMessageReceiver {
    let featureScope: FeatureScope
    let watchdogTermination: WatchdogTerminationMonitor?

    init(
        featureScope: FeatureScope,
        watchdogTermination: WatchdogTerminationMonitor?
    ) {
        self.featureScope = featureScope
        self.watchdogTermination = watchdogTermination
    }

    /// Receives `LaunchReport` from CrashReporter and starts the Watchdog Termination Monitor.
    /// - Parameters:
    ///   - message: The message containing `LaunchReport`.
    ///   - core: The `DatadogCore` instance.
    /// - Returns: `true` if the message was successfully received, `false` otherwise.
    func receive(message: DatadogInternal.FeatureMessage, from core: any DatadogInternal.DatadogCoreProtocol) -> Bool {
        do {
            guard let launch: LaunchReport? = try message.baggage(forKey: LaunchReport.messageKey) else {
                return false
            }
            watchdogTermination?.start(launchReport: launch)
            return false
        } catch {
            featureScope.telemetry.error("Fails to decode LaunchReport in RUM", error: error)
        }
        return false
    }
}
