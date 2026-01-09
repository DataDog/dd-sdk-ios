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

internal final class ScreenChangeScheduler<T: TimeProvider>: Scheduler {
    let queue: Queue = MainQueue()

    private let minimumInterval: TimeInterval
    private let telemetry: Telemetry
    private let timeProvider: T

    private var monitor: ScreenChangeMonitor<T>?
    private var operations: [() -> Void] = []

    init(minimumInterval: TimeInterval, telemetry: Telemetry, timeProvider: T) {
        self.minimumInterval = minimumInterval
        self.telemetry = telemetry
        self.timeProvider = timeProvider
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
                    timeProvider: self.timeProvider
                ) { [weak self] snapshot in
                    self?.screenDidChange(snapshot)
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

    private func screenDidChange(_ snapshot: CALayerChangeSnapshot) {
        // ScreenChangeMonitor notifies on the main thread
        DD.logger.debug("Screen changed: \(snapshot)")
        operations.forEach { $0() }
    }
}

extension ScreenChangeScheduler where T == LiveTimeProvider {
    convenience init(minimumInterval: TimeInterval, telemetry: Telemetry) {
        self.init(minimumInterval: minimumInterval, telemetry: telemetry, timeProvider: .live())
    }
}
#endif
