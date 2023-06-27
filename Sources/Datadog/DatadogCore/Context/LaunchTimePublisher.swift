/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if SPM_BUILD
import DatadogPrivate
#endif

internal struct LaunchTimePublisher: ContextValuePublisher {
    private typealias AppLaunchHandler = __dd_private_AppLaunchHandler

    let initialValue: LaunchTime?

    init() {
        initialValue = LaunchTime(
            launchTime: AppLaunchHandler.shared.launchTime?.doubleValue,
            launchDate: AppLaunchHandler.shared.launchDate,
            isActivePrewarm: AppLaunchHandler.shared.isActivePrewarm
        )
    }

    func publish(to receiver: @escaping ContextValueReceiver<LaunchTime?>) {
        let launchDate = AppLaunchHandler.shared.launchDate
        let isActivePrewarm = AppLaunchHandler.shared.isActivePrewarm

        AppLaunchHandler.shared.setApplicationDidBecomeActiveCallback { launchTime in
            let value = LaunchTime(
                launchTime: launchTime,
                launchDate: launchDate,
                isActivePrewarm: isActivePrewarm
            )
            receiver(value)
        }
    }

    func cancel() {
        AppLaunchHandler.shared.setApplicationDidBecomeActiveCallback { _ in }
    }
}
