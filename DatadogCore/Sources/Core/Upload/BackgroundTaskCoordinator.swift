/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `BackgroundTaskCoordinator` protocol provides an abstraction for managing background tasks and includes methods for registering and ending background tasks.
/// It serves as a useful abstraction for testing purposes as well as allows decoupling from UIKit in order to maintain Catalyst compliation. To abstract from UIKit, it leverages
/// the fact that UIBackgroundTaskIdentifier raw value is based on Int.
internal protocol BackgroundTaskCoordinator {
    /// Requests additional background execution time for the app.
    func beginBackgroundTask()
    /// Marks the end of a specific long-running background task.
    func endCurrentBackgroundTaskIfActive()
}

#if canImport(UIKit)
import UIKit
import DatadogInternal

/// Bridge protocol that matches UIApplication's interface for background tasks. Allows easier testablity.
internal protocol UIKitAppBackgroundTaskCoordinator {
    func beginBackgroundTask(expirationHandler handler: (() -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: UIKitAppBackgroundTaskCoordinator {}

internal class UIKitBackgroundTaskCoordinator: BackgroundTaskCoordinator {
    private let app: UIKitAppBackgroundTaskCoordinator?

    @ReadWriteLock
    private var currentTaskId: UIBackgroundTaskIdentifier?

    internal init(
        app: UIKitAppBackgroundTaskCoordinator? = UIApplication.dd.managedShared
    ) {
        self.app = app
    }

    internal func beginBackgroundTask() {
        endCurrentBackgroundTaskIfActive()
        currentTaskId = app?.beginBackgroundTask { [weak self] in
            guard let self = self else {
                return
            }
            self.endCurrentBackgroundTaskIfActive()
        }
    }

    internal func endCurrentBackgroundTaskIfActive() {
        guard let currentTaskId = currentTaskId else {
            return
        }
        if currentTaskId != .invalid {
            app?.endBackgroundTask(currentTaskId)
        }
        self.currentTaskId = nil
    }
}
#endif
