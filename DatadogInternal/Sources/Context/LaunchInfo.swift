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

/// The phase for app startup.
public enum LaunchPhase: Codable {
    case processLaunch
    case runtimeLoad
    case runtimePreMain
    case didFinishLaunching
    case didBecomeActive
}

/// Info about app launch.
public struct LaunchInfo: Codable, Equatable {
    /// The reason for app startup.
    ///
    /// While this property is typically set at SDK initialization, some products (e.g., RUM) may choose to resolve it lazily
    /// using custom heuristics. This is necessary on platforms like tvOS, where the actual launch reason cannot be determined
    /// immediately at launch time and must be inferred during a short observation window.
    public var launchReason: LaunchReason

    /// The date when the application process was started.
    public let processLaunchDate: Date

    /// The dates for app startup phases.
    public let launchPhaseDates: [LaunchPhase: Date]

    public struct Raw: Codable, Equatable {
        public let taskPolicyRole: String
        public let isPrewarmed: Bool

        public init(taskPolicyRole: String, isPrewarmed: Bool) {
            self.taskPolicyRole = taskPolicyRole
            self.isPrewarmed = isPrewarmed
        }
    }

    /// Raw data collected for app launch, used for debug purposes.
    public let raw: Raw

    public init(
        launchReason: LaunchReason,
        processLaunchDate: Date,
        runtimeLoadDate: Date?,
        runtimePreMainDate: Date?,
        didFinishLaunchingDate: Date?,
        didBecomeActiveDate: Date?,
        raw: Raw
    ) {
        self.launchReason = launchReason
        self.processLaunchDate = processLaunchDate
        var launchPhaseDates = [LaunchPhase.processLaunch: processLaunchDate]
        launchPhaseDates[.runtimeLoad] = runtimeLoadDate
        launchPhaseDates[.runtimePreMain] = runtimePreMainDate
        launchPhaseDates[.didFinishLaunching] = didFinishLaunchingDate
        launchPhaseDates[.didBecomeActive] = didBecomeActiveDate
        self.launchPhaseDates = launchPhaseDates
        self.raw = raw
    }
}
