/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

#if SPM_BUILD
import _Datadog_Private
#endif

/// Provides the application launch time.
internal protocol LaunchTimeProviderType {
    /// The app process launch duration (in seconds) measured as the time from loading the first SDK object into memory
    /// to receiving `UIApplication.didBecomeActiveNotification` notification.
    var launchTime: TimeInterval? { get }
}

internal class LaunchTimeProvider: LaunchTimeProviderType {
    var launchTime: TimeInterval? {
        // Even if AppLaunchTime() is using a lock behind the scenes, TSAN will report a data race if there are no synchronizations at this level.
        objc_sync_enter(self)
        let time = AppLaunchTime()
        objc_sync_exit(self)
        return time > 0 ? time : nil
    }
}
