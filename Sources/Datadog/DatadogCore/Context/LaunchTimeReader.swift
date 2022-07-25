/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if SPM_BUILD
import _Datadog_Private
#endif

internal struct LaunchTimeReader: ContextValueReader {
    let initialValue: LaunchTime?

    /// Lock object to sync launch time read.
    let lock: Any

    init() {
        let lock = NSObject()
        initialValue = __dd_private_objc_sync_LaunchTime(lock)
        self.lock = lock
    }

    func read(to receiver: inout LaunchTime?) {
        receiver = __dd_private_objc_sync_LaunchTime(lock)
    }
}

private func __dd_private_objc_sync_LaunchTime(_ lock: Any) -> LaunchTime {
    // Even if __dd_private_AppLaunchTime() is using a lock behind the
    // scenes, TSAN will report a data race if there are no
    // synchronizations at this level.
    objc_sync_enter(lock)
    let time = LaunchTime(
        launchTime: __dd_private_AppLaunchTime(),
        isActivePrewarm: __dd_private_isActivePrewarm()
    )
    objc_sync_exit(lock)
    return time
}
