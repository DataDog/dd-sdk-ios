/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the application launch time.
internal struct LaunchTime {
    /// The app process launch duration (in seconds) measured as the time from process start time
    /// to receiving `UIApplication.didBecomeActiveNotification` notification.
    ///
    /// If the `UIApplication.didBecomeActiveNotification` has not yet been received by the
    /// time this value is provided, it will represent the time interval between now and the process start time.
    let launchTime: TimeInterval

    /// Returns `true` if the application is pre-warmed.
    let isActivePrewarm: Bool
}
