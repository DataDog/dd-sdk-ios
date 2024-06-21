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

/// Checks if the app was terminated by Watchdog using heuristics.
/// It uses the app state information from the last app session and the current app session
/// to determine if the app was terminated by Watchdog.
internal final class WatchdogTerminationChecker {
    let appStateManager: WatchdogTerminationAppStateManager
    let deviceInfo: DeviceInfo

    init(
        appStateManager: WatchdogTerminationAppStateManager,
        deviceInfo: DeviceInfo
    ) {
        self.appStateManager = appStateManager
        self.deviceInfo = deviceInfo
    }

    /// Checks if the app was terminated by Watchdog.
    /// - Parameters:
    ///   - launch: The launch report containing information about the app launch.
    ///   - completion: The completion block called with the result.
    func isWatchdogTermination(launch: LaunchReport, completion: @escaping (Bool, WatchdogTerminationAppState?) -> Void) throws {
        do {
            try appStateManager.currentAppState { current in
                self.appStateManager.readAppState { [weak self] previous in
                    guard let self = self else {
                        completion(false, current)
                        return
                    }
                    completion(self.isWatchdogTermination(launch: launch, from: previous, to: current), current)
                }
            }
        } catch let error {
            DD.logger.error("Failed to check if Watchdog Termination occurred", error: error)
            completion(false, nil)
            throw error
        }
    }

    /// Checks if the app was terminated by Watchdog.
    /// - Parameters:
    ///  - launch: The launch report containing information about the app launch.
    ///  - previous: The previous app state stored in the data store from the last app session.
    ///  - current: The current app state of the app.
    func isWatchdogTermination(
        launch: LaunchReport,
        from previous: WatchdogTerminationAppState?,
        to current: WatchdogTerminationAppState
    ) -> Bool {
        DD.logger.debug(launch.debugDescription)
        DD.logger.debug(previous.debugDescription)
        DD.logger.debug(current.debugDescription)

        guard let previous = previous else {
            return false
        }

        // Watchdog Termination detection doesn't work on simulators.
        guard deviceInfo.isSimulator == false else {
            return false
        }

        // When the app is running in debug mode, we can't reliably tell if it was a Watchdog Termination or not.
        guard previous.isDebugging == false else {
           return false
        }

        // Is the app version different than the last time the app was opened?
        guard previous.appVersion == current.appVersion else {
            return false
        }

        // Is there a crash from the last time the app was opened?
        guard launch.didCrash == false else {
            return false
        }

        // Did we receive a termination call the last time the app was opened?
        guard previous.wasTerminated == false else {
            return false
        }

        // Is the OS version different than the last time the app was opened?
        guard previous.osVersion == current.osVersion else {
            return false
        }

        // Was the system rebooted since the last time the app was opened?
        guard previous.systemBootTime == current.systemBootTime else {
            return false
        }

        // This value can change when installing test builds using Xcode or when installing an app
        // on a device using ad-hoc distribution.
        guard previous.vendorId == current.vendorId else {
            return false
        }

        // This is likely same process but another check due to stop & start of the SDK
        guard previous.processId != current.processId else {
            return false
        }

        // Was the app in foreground/active ?
        // If the app was in background we can't reliably tell if it was a Watchdog Termination or not.
        guard previous.isActive else {
            return false
        }

        return true
    }
}
