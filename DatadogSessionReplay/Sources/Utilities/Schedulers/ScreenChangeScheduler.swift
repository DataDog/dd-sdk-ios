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

    private let minimumInterval: TimeInterval
    private let telemetry: Telemetry
    private let timerScheduler: any TimerScheduler

    private var monitor: ScreenChangeMonitor?
    private var operations: [() -> Void] = []

    init(
        minimumInterval: TimeInterval,
        telemetry: Telemetry,
        timerScheduler: any TimerScheduler = .dispatchSource
    ) {
        self.minimumInterval = minimumInterval
        self.telemetry = telemetry
        self.timerScheduler = timerScheduler
    }

    func schedule(operation: @escaping () -> Void) {
        queue.run {
            self.operations.append(operation)
        }
    }

    func start() {
        queue.run {
            guard self.monitor == nil else {
                return // already started
            }

            do {
                let monitor = try ScreenChangeMonitor(
                    minimumDeliveryInterval: self.minimumInterval,
                    timerScheduler: self.timerScheduler
                ) { [weak self] changes in
                    self?.screenDidChange(changes)
                }
                monitor.start()
                self.monitor = monitor
            } catch {
                self.telemetry.error("[SR] Could not create ScreenChangeMonitor", error: error)
            }
        }
    }

    func stop() {
        queue.run {
            guard let monitor = self.monitor else {
                return
            }
            monitor.stop()
            self.monitor = nil
        }
    }

    private func screenDidChange(_ changes: CALayerChangeset) {
        // ScreenChangeMonitor notifies on the main thread
        DD.logger.debug("Screen changed: \(changes)")
        operations.forEach { $0() }
    }
}
#endif
