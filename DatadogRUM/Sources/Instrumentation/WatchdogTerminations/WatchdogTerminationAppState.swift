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

/// Represents the app state observed during application lifecycle events such as application start, resume and termination.
/// This state is used to detect Watchdog Terminations.
internal struct WatchdogTerminationAppState: Codable {
    /// The Application version provided by the `Bundle`.
    let appVersion: String

    /// The Operating System version.
    let osVersion: String

    /// Last time the system was booted.
    let systemBootTime: TimeInterval

    /// Returns true, if the app is running with a debug configuration.
    let isDebugging: Bool

    /// Returns true, if the app was terminated normally.
    var wasTerminated: Bool

    /// Returns true, if the app was in the foreground.
    var isActive: Bool

    /// The vendor identifier of the device.
    /// This value can change when installing test builds using Xcode or when installing an app on a device using ad-hoc distribution.
    let vendorId: String?
}
