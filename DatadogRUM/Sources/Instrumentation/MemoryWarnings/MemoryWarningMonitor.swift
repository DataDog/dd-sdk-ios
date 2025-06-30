/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

/// Tracks the memory warnings history and publishes it to the subscribers.
internal final class MemoryWarningMonitor {
    let notificationCenter: NotificationCenter
    let reporter: MemoryWarningReporting

    init(
        memoryWarningReporter: MemoryWarningReporting,
        notificationCenter: NotificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.reporter = memoryWarningReporter
    }

    /// Starts monitoring memory warnings by subscribing to `UIApplication.didReceiveMemoryWarningNotification`.
    func start() {
        notificationCenter.addObserver(self, selector: #selector(didReceiveMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    @objc
    func didReceiveMemoryWarning() {
        reporter.reportMemoryWarning()
    }

    /// Stops monitoring memory warnings.
    func stop() {
        notificationCenter.removeObserver(self)
    }
}
