/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `BackgroundTaskCoordinator` protocol provides an abstraction for managing background tasks and includes methods for registering and ending background tasks.
internal protocol BackgroundTaskCoordinator {
    /// Begins a background task, requesting additional background execution time for the app.
    /// Calling it multiple times will end the previous background task and start a new one.
    /// It internally implements system handler for background task expiration which will end current background task.
    func beginBackgroundTask()
    /// Marks the end of a background task.
    func endBackgroundTask()
}

#if canImport(UIKit)
import UIKit
import DatadogInternal

/// Bridge protocol that calls corresponding `UIApplication` interface for background tasks. Allows easier testablity.
internal protocol UIKitAppBackgroundTaskCoordinator {
    func beginBgTask(_ handler: (() -> Void)?) -> UIBackgroundTaskIdentifier
    func endBgTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: UIKitAppBackgroundTaskCoordinator {
    func beginBgTask(_ handler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
        return beginBackgroundTask {
            handler?()
        }
    }
    func endBgTask(_ identifier: UIBackgroundTaskIdentifier) {
        endBackgroundTask(identifier)
    }
}

internal class AppBackgroundTaskCoordinator: BackgroundTaskCoordinator {
    private let app: UIKitAppBackgroundTaskCoordinator?

    @ReadWriteLock
    private var currentTaskId: UIBackgroundTaskIdentifier?

    internal init(
        app: UIKitAppBackgroundTaskCoordinator? = UIApplication.dd.managedShared
    ) {
        self.app = app
    }

    internal func beginBackgroundTask() {
        endBackgroundTask()
        currentTaskId = app?.beginBgTask { [weak self] in
            guard let self = self else {
                return
            }
            self.endBackgroundTask()
        }
    }

    internal func endBackgroundTask() {
        guard let currentTaskId = currentTaskId else {
            return
        }
        if currentTaskId != .invalid {
            app?.endBgTask(currentTaskId)
        }
        self.currentTaskId = nil
    }
}

/// Bridge protocol that matches `ProcessInfo` interface for background activity. Allows easier testablity.
internal protocol ProcessInfoActivityCoordinator {
    func beginActivity(options: ProcessInfo.ActivityOptions, reason: String) -> any NSObjectProtocol
    func endActivity(_ activity: any NSObjectProtocol)
}

extension ProcessInfo: ProcessInfoActivityCoordinator {}

internal class ExtensionBackgroundTaskCoordinator: BackgroundTaskCoordinator {
    private let processInfo: ProcessInfoActivityCoordinator

    @ReadWriteLock
    private var currentActivity: NSObjectProtocol?

    internal init(
        processInfo: ProcessInfoActivityCoordinator = ProcessInfo()
    ) {
        self.processInfo = processInfo
    }

    internal func beginBackgroundTask() {
        endBackgroundTask()
        currentActivity = processInfo.beginActivity(options: [.background], reason: "Datadog SDK background upload")
    }

    internal func endBackgroundTask() {
        guard let currentActivity = currentActivity else {
            return
        }
        processInfo.endActivity(currentActivity)
        self.currentActivity = nil
    }
}
#endif
