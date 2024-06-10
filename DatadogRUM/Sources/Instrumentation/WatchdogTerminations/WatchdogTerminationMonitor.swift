/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if canImport(UIKit)
import UIKit
#endif

internal final class WatchdogTerminationReporter {
    func send() {
        DD.logger.error("TODO: WatchdogTerminationReporter.report()")
    }
}

/// Monitors the Watchdog Termination events and reports them to Datadog.
internal final class WatchdogTerminationMonitor {
    enum ErrorMessages {
        static let failedToCheckWatchdogTermination = "Failed to check if Watchdog Termination occurred"
        static let failedToStartAppState = "Failed to start Watchdog Termination App State Manager"
        static let failedToStopAppState = "Failed to stop Watchdog Termination App State Manager"
        static let detectedWatchdogTermination = "Based on heuristics, previous app session was terminated by Watchdog"
        static let detectedNonWatchdogTermination = "Previous app session was not terminated by Watchdog"
    }

    let checker: WatchdogTerminationChecker
    let appStateManager: WatchdogTerminationAppStateManager
    let telemetry: Telemetry
    let reporter: WatchdogTerminationReporter

    init(
        checker: WatchdogTerminationChecker,
        appStateManager: WatchdogTerminationAppStateManager,
        reporter: WatchdogTerminationReporter,
        telemetry: Telemetry
    ) {
        self.checker = checker
        self.appStateManager = appStateManager
        self.telemetry = telemetry
        self.reporter = reporter
    }

    /// Starts the Watchdog Termination Monitor.
    /// - Parameter launchReport: The launch report containing information about the app launch (if available).
    func start(launchReport: LaunchReport?) {
        if let launchReport = launchReport {
            sendWatchTerminationIfFound(launch: launchReport)
        }

        do {
            try appStateManager.start()
        } catch let error {
            DD.logger.error(ErrorMessages.failedToStartAppState, error: error)
            telemetry.error(ErrorMessages.failedToStartAppState, error: error)
        }
    }

    private func sendWatchTerminationIfFound(launch: LaunchReport) {
        defer {
            self.appStateManager.deleteAppState()
        }
        do {
            try checker.isWatchdogTermination(launch: launch) { isWatchdogTermination in
                if isWatchdogTermination {
                    DD.logger.debug(ErrorMessages.detectedWatchdogTermination)
                    self.reporter.send()
                } else {
                    DD.logger.debug(ErrorMessages.detectedNonWatchdogTermination)
                }
            }
        } catch let error {
            DD.logger.error(ErrorMessages.failedToCheckWatchdogTermination, error: error)
            telemetry.error(ErrorMessages.failedToCheckWatchdogTermination, error: error)
        }
    }

    /// Stops the Watchdog Termination Monitor.
    func stop() {
        do {
            try appStateManager.stop()
        } catch {
            DD.logger.error(ErrorMessages.failedToStopAppState, error: error)
            telemetry.error(ErrorMessages.failedToStopAppState, error: error)
        }
    }
}
