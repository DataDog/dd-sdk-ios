/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Produces `isLowPowerModeEnabled` updates via `AsyncStream` by observing the
/// `NSProcessInfoPowerStateDidChange` notification.
internal struct LowPowerModeSource: ContextValueSource {
    let initialValue: Bool
    let values: AsyncStream<Bool>

    init(
        notificationCenter: NotificationCenter,
        processInfo: ProcessInfo
    ) {
        self.initialValue = processInfo.isLowPowerModeEnabled

        self.values = AsyncStream { continuation in
            nonisolated(unsafe) let observer = notificationCenter
                .addObserver(
                    forName: .NSProcessInfoPowerStateDidChange,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let processInfo = notification.object as? ProcessInfo else {
                        return
                    }

                    // We suspect an iOS 15 bug (ref.: https://openradar.appspot.com/FB9741207) which leads to rare
                    // `_os_unfair_lock_recursive_abort` crash when `processInfo.isLowPowerModeEnabled` is accessed
                    // directly in the notification handler. As a workaround, we defer its access to the next run loop
                    // where underlying lock should be already released.
                    OperationQueue.main.addOperation {
                        continuation.yield(processInfo.isLowPowerModeEnabled)
                    }
                }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }
}
