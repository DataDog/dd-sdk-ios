/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if SPM_BUILD
import _Datadog_Private
#endif

internal struct LaunchTimePublisher: ContextValuePublisher {
    private typealias AppLaunchHandler = __dd_private_AppLaunchHandler

    let initialValue: LaunchTime

    init() {
        initialValue = LaunchTime(
            launchTime: AppLaunchHandler.shared.launchTime?.doubleValue,
            launchDate: AppLaunchHandler.shared.launchDate,
            isActivePrewarm: AppLaunchHandler.shared.isActivePrewarm
        )
    }

    func publish(to receiver: @escaping ContextValueReceiver<LaunchTime>) {
        AppLaunchHandler.shared.setApplicationDidBecomeActiveCallback { launchTime in
            let value = LaunchTime(
                launchTime: launchTime,
                launchDate: initialValue.launchDate,
                isActivePrewarm: initialValue.isActivePrewarm
            )
            receiver(value)
        }
    }

    func cancel() {
        AppLaunchHandler.shared.setApplicationDidBecomeActiveCallback { _ in }
    }
}
