/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Adapter that bridges `ScreenChangeMonitor` to the Scheduler protocol.
//
// This scheduler executes the scheduled operations when screen changes are detected
// (display, draw, layout), rate-limited to a minimum interval. Unlike timer-based
// scheduling, this approach executes operations only when visual changes occur,
// reducing unnecessary work.

#if os(iOS)
import Foundation
import DatadogInternal

internal final class ScreenChangeScheduler: Scheduler {
    let queue: Queue = MainQueue()

    private let monitor: ScreenChangeMonitor
    private var operations: [() -> Void] = []

    convenience init(
        minimumInterval: TimeInterval,
        telemetry: Telemetry,
        timerScheduler: any TimerScheduler = .dispatchSource
    ) throws {
        try self.init(
            monitor: ScreenChangeMonitor(
                minimumDeliveryInterval: minimumInterval,
                timerScheduler: timerScheduler
            )
        )
    }

    init(monitor: ScreenChangeMonitor) {
        self.monitor = monitor

        monitor.handler = { [weak self] changes in
            self?.screenDidChange(changes)
        }
    }

    func schedule(operation: @escaping () -> Void) {
        queue.run {
            self.operations.append(operation)
        }
    }

    func start() {
        queue.run {
            self.monitor.start()
        }
    }

    func stop() {
        queue.run {
            self.monitor.stop()
        }
    }

    private func screenDidChange(_ changes: CALayerChangeset) {
        // ScreenChangeMonitor notifies on the main thread
        DD.logger.debug("Screen changed: \(changes)")
        operations.forEach { $0() }
    }
}
#endif
