/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Used by `LongTaskObserver` to avoid creating Long Task commands when the
/// application is in background (iOS) or the system is about to sleep (macOS).
internal protocol LongTaskObserverBackgroundStateProvider {
    var isInBackgroundState: Bool { get }
}

#if os(macOS)
internal class DefaultLongTaskObserverBackgroundStateProvider: LongTaskObserverBackgroundStateProvider {
    private let notificationCenter: NotificationCenter
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?
    private var isInSleepState = false

    init(notificationCenterProvider: NotificationCenterProvider) {
        self.notificationCenter = notificationCenterProvider.workspaceCenter

        willSleepObserver = notificationCenter.addObserver(
            forName: WorkspaceNotifications.willSleep,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                self?.isInSleepState = true
            }
        )

        didWakeObserver = notificationCenter.addObserver(
            forName: WorkspaceNotifications.didWake,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                self?.isInSleepState = false
            }
        )
    }

    deinit {
        willSleepObserver.map { notificationCenter.removeObserver($0) }
        didWakeObserver.map { notificationCenter.removeObserver($0) }
    }

    var isInBackgroundState: Bool {
        isInSleepState
    }
}
#elseif os(watchOS)
import WatchKit

internal class DefaultLongTaskObserverBackgroundStateProvider: LongTaskObserverBackgroundStateProvider {
    var isInBackgroundState: Bool {
        WKApplication.shared().applicationState == .background
    }
}
#else
import UIKit

internal class DefaultLongTaskObserverBackgroundStateProvider: LongTaskObserverBackgroundStateProvider {
    var isInBackgroundState: Bool {
        UIApplication.dd.managedShared?.applicationState == .background
    }
}
#endif
