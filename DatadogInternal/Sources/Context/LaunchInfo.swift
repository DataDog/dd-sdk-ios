/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The reason for app startup.
public enum LaunchReason: Codable {
    /// The app was launched by direct user interaction (e.g., tapping the app icon).
    case userLaunch
    /// The app was launched in the background by the system (e.g., background fetch or silent push).
    case backgroundLaunch
    /// The app was prewarmed by the OS to reduce perceived launch time (iOS only).
    case prewarming
    /// The launch reason could not be determined due to platform limitations (e.g., tvOS)
    /// or inability to retrieve `task_role_t` in `__dd_private_AppLaunchHandler`.
    case uncertain
}

/// Info about app launch.
public struct LaunchInfo: Codable, Equatable, PassthroughAnyCodable {
    /// The reason for app startup.
    public let launchReason: LaunchReason

    /// The date when the application process was started.
    public let processLaunchDate: Date

    /// The duration measured from `processLaunchDate` to receiving `UIApplication.didBecomeActiveNotification`.
    /// If the notification has not yet been received the value will be `nil`.
    public let timeToDidBecomeActive: TimeInterval?

    public init(
        launchReason: LaunchReason,
        processLaunchDate: Date,
        timeToDidBecomeActive: TimeInterval?
    ) {
        self.launchReason = launchReason
        self.processLaunchDate = processLaunchDate
        self.timeToDidBecomeActive = timeToDidBecomeActive
    }
}
