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
    /// The app process launch duration (in seconds) measured as the time from process start time
    /// to receiving `UIApplication.didBecomeActiveNotification` notification.
    ///
    /// If the `UIApplication.didBecomeActiveNotification` has not yet been received by the
    /// time this variable is requested, the value should represent the time interval between now and the
    /// process start time.
    var launchTime: TimeInterval { get }

    /// Returns `true` if the application is pre-warmed.
    var isActivePrewarm: Bool { get }
}

internal class LaunchTimeProvider: LaunchTimeProviderType {
    var launchTime: TimeInterval {
        // Even if __dd_private_AppLaunchTime() is using a lock behind the
        // scenes, TSAN will report a data race if there are no
        // synchronizations at this level.
        objc_sync_enter(self)
        let time = __dd_private_AppLaunchTime()
        objc_sync_exit(self)
        return time
    }

    var isActivePrewarm: Bool {
        objc_sync_enter(self)
        let isActivePrewarm = __dd_private_isActivePrewarm()
        objc_sync_exit(self)
        return isActivePrewarm
    }
}
