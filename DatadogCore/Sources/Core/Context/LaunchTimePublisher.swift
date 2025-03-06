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

/// An interface for tracking key timestamps in the app launch sequence, including launch time and activation events.
internal protocol AppLaunchHandling {
    /// Indicates whether the application was prewarmed by the system.
    var isActivePrewarm: Bool { get }
    /// The timestamp when the application process was launched.
    var launchDate: Date { get }
    /// The time interval between the app process launch and the `UIApplication.didBecomeActiveNotification`.
    /// Returns `nil` if the notification has not yet been received.
    var timeToDidBecomeActive: TimeInterval? { get }
    /// Sets a callback to be invoked when the application becomes active.
    ///
    /// The callback receives the time interval from process launch to app activation.
    /// If the application became active before setting the callback, it will not be triggered.
    ///
    /// - Parameter callback: A closure executed upon app activation.
    func setApplicationDidBecomeActiveCallback(_ callback: @escaping UIApplicationDidBecomeActiveCallback)
}

internal extension AppLaunchHandling {
    /// Returns latest available launch time information.
    var currentValue: LaunchTime {
        return LaunchTime(
            launchTime: timeToDidBecomeActive,
            launchDate: launchDate,
            isActivePrewarm: isActivePrewarm
        )
    }
}

internal typealias AppLaunchHandler = __dd_private_AppLaunchHandler

extension AppLaunchHandler: AppLaunchHandling {
    var timeToDidBecomeActive: TimeInterval? { launchTime?.doubleValue }
}

#if !os(macOS)

internal struct LaunchTimePublisher: ContextValuePublisher {
    private let handler: AppLaunchHandling

    let initialValue: LaunchTime

    init(handler: AppLaunchHandling) {
        self.initialValue = handler.currentValue
        self.handler = handler
    }

    func publish(to receiver: @escaping ContextValueReceiver<LaunchTime>) {
        let launchDate = handler.launchDate
        let isActivePrewarm = handler.isActivePrewarm

        handler.setApplicationDidBecomeActiveCallback { launchTime in
            let value = LaunchTime(
                launchTime: launchTime,
                launchDate: launchDate,
                isActivePrewarm: isActivePrewarm
            )
            receiver(value)
        }
    }

    func cancel() {
        handler.setApplicationDidBecomeActiveCallback { _ in }
    }
}

#endif
