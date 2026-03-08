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
    /// The current process's task policy role (`task_role_t`), indicating how the process was started (e.g., user vs background launch).
    /// On success, the property contains the raw [`policy.role`](https://developer.apple.com/documentation/kernel/task_role_t) value
    /// defined in `MachO`; otherwise, it returns one of the special constants defined in `ObjcAppLaunchHandler.h`:
    /// - `__dd_private_TASK_POLICY_KERN_FAILURE`
    /// - `__dd_private_TASK_POLICY_DEFAULTED`
    /// - `__dd_private_TASK_POLICY_UNAVAILABLE`
    var taskPolicyRole: Int { get }

    /// The date when the application process was launched.
    var processLaunchDate: Date { get }

    /// The date when the SDK was loaded.
    var runtimeLoadDate: Date { get }

    /// The date right before the @c main() is executed.
    var runtimePreMainDate: Date { get }

    /// Sets a callback to be invoked when the application receives UIApplication notifications.
    ///
    /// - Parameter callback: A closure executed upon app activation.
    func setApplicationNotificationCallback(_ callback: @escaping UIApplicationNotificationCallback)
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
            runtimeLoadDate: runtimeLoadDate,
            runtimePreMainDate: runtimePreMainDate,
            raw: .init(
                taskPolicyRole: rawTaskPolicyRole,
                isPrewarmed: isPrewarmed(processInfo: processInfo)
            )
        )
    }

    private func resolveLaunchReason(using processInfo: ProcessInfo) -> LaunchReason {
        let isUserLaunch = taskPolicyRole == TASK_FOREGROUND_APPLICATION.rawValue
        let isUnavailable = taskPolicyRole == __dd_private_TASK_POLICY_UNAVAILABLE

        guard !isUnavailable else {
            return .uncertain
        }

        if isPrewarmed(processInfo: processInfo) {
            return .prewarming
        } else if isUserLaunch {
            return .userLaunch
        } else {
            return .backgroundLaunch
        }
    }

    private func isPrewarmed(processInfo: ProcessInfo) -> Bool {
        return processInfo.environment["ActivePrewarm"] == "1"
    }

    private var rawTaskPolicyRole: String {
        switch taskPolicyRole {
        case Int(TASK_BACKGROUND_APPLICATION.rawValue):     return "TASK_BACKGROUND_APPLICATION"
        case Int(TASK_CONTROL_APPLICATION.rawValue):        return "TASK_CONTROL_APPLICATION"
        case Int(TASK_DARWINBG_APPLICATION.rawValue):       return "TASK_DARWINBG_APPLICATION"
        case Int(TASK_DEFAULT_APPLICATION.rawValue):        return "TASK_DEFAULT_APPLICATION"
        case Int(TASK_FOREGROUND_APPLICATION.rawValue):     return "TASK_FOREGROUND_APPLICATION"
        case Int(TASK_GRAPHICS_SERVER.rawValue):            return "TASK_GRAPHICS_SERVER"
        case Int(TASK_NONUI_APPLICATION.rawValue):          return "TASK_NONUI_APPLICATION"
        case Int(TASK_RENICED.rawValue):                    return "TASK_RENICED"
        case Int(TASK_THROTTLE_APPLICATION.rawValue):       return "TASK_THROTTLE_APPLICATION"
        case Int(TASK_UNSPECIFIED.rawValue):                return "TASK_UNSPECIFIED"
        case __dd_private_TASK_POLICY_UNAVAILABLE:          return "__dd_private_TASK_POLICY_UNAVAILABLE"
        case __dd_private_TASK_POLICY_DEFAULTED:            return "__dd_private_TASK_POLICY_DEFAULTED"
        case __dd_private_TASK_POLICY_KERN_FAILURE:         return "__dd_private_TASK_POLICY_KERN_FAILURE"
        default:
            return "unknown (\(taskPolicyRole))"
        }
    }
}

#if !os(macOS)

/// Produces `LaunchInfo` updates via `AsyncStream`.
///
/// A single enriched `LaunchInfo` value is yielded once the `AppLaunchHandling`
/// callback fires with `didFinishLaunching` / `didBecomeActive` dates.
internal struct LaunchInfoSource: ContextValueSource {
    let initialValue: LaunchInfo
    let values: AsyncStream<LaunchInfo>

    init(handler: AppLaunchHandling, initialValue: LaunchInfo) {
        self.initialValue = initialValue

        let capturedInitialValue = initialValue
        self.values = AsyncStream { continuation in
            handler.setApplicationNotificationCallback { didFinishLaunchingDate, didBecomeActiveDate in
                let value = LaunchInfo(
                    launchReason: capturedInitialValue.launchReason,
                    processLaunchDate: capturedInitialValue.processLaunchDate,
                    runtimeLoadDate: capturedInitialValue.launchPhaseDates[.runtimeLoad],
                    runtimePreMainDate: capturedInitialValue.launchPhaseDates[.runtimePreMain],
                    didFinishLaunchingDate: didFinishLaunchingDate,
                    didBecomeActiveDate: didBecomeActiveDate,
                    raw: capturedInitialValue.raw
                )
                continuation.yield(value)
            }
        }
    }
}

#endif
