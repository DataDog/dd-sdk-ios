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
    let backtraceReporter: BacktraceReporting?
    let reporter: MemoryWarningReporting

    init(
        backtraceReporter: BacktraceReporting?,
        memoryWarningReporter: MemoryWarningReporting,
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationCenter = notificationCenter
        self.backtraceReporter = backtraceReporter
        self.reporter = memoryWarningReporter
    }

    /// Starts monitoring memory warnings by subscribing to `UIApplication.didReceiveMemoryWarningNotification`.
    func start() {
        notificationCenter.addObserver(self, selector: #selector(didReceiveMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    @objc
    func didReceiveMemoryWarning() {
        let date: Date = .init()
        let backtrace: BacktraceReport?
        do {
            backtrace = try backtraceReporter?.generateBacktrace()
        } catch {
            backtrace = nil
        }
        let warning = MemoryWarning(date: date, backtrace: backtrace)

        reporter.report(warning: warning)
    }

    /// Stops monitoring memory warnings.
    func stop() {
        notificationCenter.removeObserver(self)
    }
}
