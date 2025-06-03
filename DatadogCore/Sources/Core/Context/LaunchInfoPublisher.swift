/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if SPM_BUILD
    #if swift(>=6.0)
    internal import DatadogPrivate
    #else
    @_implementationOnly import DatadogPrivate
    #endif
#endif
// swiftlint:enable duplicate_imports

/// An interface for tracking key timestamps in the app launch sequence, including launch time and activation events.
internal protocol AppLaunchHandling {
    /// The current process’s task policy role (`task_role_t`), indicating how the process was started (e.g., user vs background launch).
    /// On success, the property contains the raw [`policy.role`](https://developer.apple.com/documentation/kernel/task_role_t) value
    /// defined in `MachO`; otherwise, it returns one of the special constants defined in `ObjcAppLaunchHandler.h`:
    /// - `__dd_private_TASK_POLICY_KERN_FAILURE`
    /// - `__dd_private_TASK_POLICY_DEFAULTED`
    /// - `__dd_private_TASK_POLICY_UNAVAILABLE`
    var taskPolicyRole: Int { get }

    /// The timestamp when the application process was launched.
    var processLaunchDate: Date { get }

    /// The time interval (in seconds) between the `processLaunchDate` and the `UIApplication.didBecomeActiveNotification`.
    /// Returns `nil` if the notification has not yet been received.
    var timeToDidBecomeActive: NSNumber? { get }

    /// Sets a callback to be invoked when the application becomes active.
    ///
    /// The callback receives the time interval from process launch to app activation.
    /// The callback must be triggered only once upon the next `UIApplicationDidBecomeActiveNotification`
    /// and should be not retained for subsequent activations.
    ///
    /// - Parameter callback: A closure executed upon app activation.
    func setApplicationDidBecomeActiveCallback(_ callback: @escaping UIApplicationDidBecomeActiveCallback)
}

/// Conforms `__dd_private_AppLaunchHandler` (objc) to `AppLaunchHandling` (Swift).
extension __dd_private_AppLaunchHandler: AppLaunchHandling {}

internal typealias AppLaunchHandler = __dd_private_AppLaunchHandler

extension AppLaunchHandling {
    /// Resolves the current launch information using internal state and provided `ProcessInfo`.
    func resolveLaunchInfo(using processInfo: ProcessInfo) -> LaunchInfo {
        return LaunchInfo(
            launchReason: resolveLaunchReason(using: processInfo),
            processLaunchDate: processLaunchDate,
            timeToDidBecomeActive: timeToDidBecomeActive?.doubleValue
        )
    }

    private func resolveLaunchReason(using processInfo: ProcessInfo) -> LaunchReason {
        let isPrewarmed = processInfo.environment["ActivePrewarm"] == "1"
        let isUserLaunch = taskPolicyRole == TASK_FOREGROUND_APPLICATION.rawValue
        let isUnavailable = taskPolicyRole == __dd_private_TASK_POLICY_UNAVAILABLE

        guard !isUnavailable else {
            return .uncertain
        }

        if isPrewarmed {
            return .prewarming
        } else if isUserLaunch {
            return .userLaunch
        } else {
            return .backgroundLaunch
        }
    }
}

#if !os(macOS)

internal struct LaunchInfoPublisher: ContextValuePublisher {
    private let handler: AppLaunchHandling

    let initialValue: LaunchInfo

    init(handler: AppLaunchHandling, initialValue: LaunchInfo) {
        self.initialValue = initialValue
        self.handler = handler
    }

    func publish(to receiver: @escaping ContextValueReceiver<LaunchInfo>) {
        let initialValue = initialValue

        handler.setApplicationDidBecomeActiveCallback { timeToDidBecomeActive in
            let value = LaunchInfo(
                launchReason: initialValue.launchReason,
                processLaunchDate: initialValue.processLaunchDate,
                timeToDidBecomeActive: timeToDidBecomeActive
            )
            receiver(value)
        }
    }

    func cancel() {
        handler.setApplicationDidBecomeActiveCallback { _ in }
    }
}

#endif
