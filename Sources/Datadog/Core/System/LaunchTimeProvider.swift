/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import _Datadog_Private

/// Provides the application launch time.
internal protocol LaunchTimeProviderType {
    /// The app process launch duration (in seconds) measured as the time from loading the first SDK object into memory
    /// to receiving `UIApplication.didBecomeActiveNotification` notification.
    var launchTime: TimeInterval? { get }
}

internal class LaunchTimeProvider: LaunchTimeProviderType {
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(
        label: "com.datadoghq.launch-time-provider", qos: .userInteractive
    )

    // MARK: - Initialization

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        notificationCenter.addObserver(
            self, selector: #selector(stopLaunchTimer), name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    // MARK: - Measurement

    @objc
    private func stopLaunchTimer() {
        let launchTime = ObjcAppLaunchHandler.measureTimeToNow()
        notificationCenter.removeObserver(self)
        queue.async { self.unsafeLaunchTime = launchTime }
    }

    // MARK: - LaunchTimeProviderType

    private var unsafeLaunchTime: TimeInterval?

    var launchTime: TimeInterval? {
        queue.sync { unsafeLaunchTime }
    }
}
