/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The low power mode publisher will publish the ``ProcessInfo/isLowPowerModeEnabled`` value
/// by observing the `NSProcessInfoPowerStateDidChange` notification on the given
/// notification center.
internal final class LowPowerModePublisher: ContextValuePublisher {
    let initialValue: Bool

    private let notificationCenter: NotificationCenter
    private var observer: Any?

    /// Creates a low power mode publisher.
    ///
    /// - Parameters:
    ///   - notificationCenter: The notification center for observing the `NSProcessInfoPowerStateDidChange`,
    ///   - processInfo: The process for reading the initial `isLowPowerModeEnabled`.
    init(
        notificationCenter: NotificationCenter,
        processInfo: ProcessInfo
    ) {
        self.initialValue = processInfo.isLowPowerModeEnabled
        self.notificationCenter = notificationCenter
    }

    func publish(to receiver: @escaping ContextValueReceiver<Bool>) {
        self.observer = notificationCenter
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
                    receiver(processInfo.isLowPowerModeEnabled)
                }
            }
    }

    func cancel() {
        observer.map(notificationCenter.removeObserver)
    }
}
