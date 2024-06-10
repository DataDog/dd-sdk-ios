//
//  LaunchReportReceiver.swift
//  Datadog
//
//  Created by Ganesh Jangir on 03/06/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

import Foundation
import DatadogInternal

/// Receives `LaunchReport` from CrashReporter and starts the Watchdog Termination Monitor.
internal struct LaunchReportReceiver: FeatureMessageReceiver {
    let featureScope: FeatureScope
    let watchdogTermination: WatchdogTerminationMonitor?

    init(featureScope: FeatureScope, watchdogTermination: WatchdogTerminationMonitor?) {
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
            let launch: LaunchReport? = try message.baggage(forKey: LaunchReport.messageKey)
            watchdogTermination?.start(launchReport: launch)
            return true
        } catch {
            featureScope.telemetry.error("Fails to decode launch from RUM", error: error)
        }
        return false
    }
}
