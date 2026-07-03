/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Runs scheduled work when the screen changes.
///
/// It uses `ScreenChangeMonitor` to detect layer display, draw, and layout
/// changes, then runs scheduled operations at most once per minimum interval.
/// This avoids waking the recorder when nothing visual changed.
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
                ) { [weak self] changeset in
                    self?.screenDidChange(changeset)
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

    private func screenDidChange(_ changeset: CALayerChangeset) {
        // ScreenChangeMonitor notifies on the main thread
        DD.logger.debug("Screen changed: \(changeset)")
        operations.forEach { $0() }
    }
}
#endif
