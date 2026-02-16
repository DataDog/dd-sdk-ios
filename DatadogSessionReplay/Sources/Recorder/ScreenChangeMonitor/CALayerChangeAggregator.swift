/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Aggregates observed `CALayer` changes over time and delivers them at a
// minimum interval. Records which aspects changed per layer and invokes a
// handler with a `CALayerChangeset` for batching, correlation, and reporting.

#if os(iOS)
import QuartzCore

internal final class CALayerChangeAggregator {
    var handler: ((CALayerChangeset) -> Void)?

    private let minimumDeliveryInterval: TimeInterval
    private let timerScheduler: any TimerScheduler

    private var isRunning = false
    private var pendingChanges: [ObjectIdentifier: CALayerChange] = [:]
    private var lastDeliveryTime: TimeInterval?
    private var scheduledDelivery: (any ScheduledTimer)?

    init(minimumDeliveryInterval: TimeInterval, timerScheduler: any TimerScheduler) {
        self.minimumDeliveryInterval = minimumDeliveryInterval
        self.timerScheduler = timerScheduler
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        lastDeliveryTime = timerScheduler.now
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        pendingChanges.removeAll()
        scheduledDelivery?.cancel()
        scheduledDelivery = nil
    }

    private func record(_ layer: CALayer, aspect: CALayerChange.Aspect.Set) {
        // Only record on the main thread
        guard Thread.isMainThread, isRunning else {
            return
        }

        let id = ObjectIdentifier(layer)

        // Merge aspects for the same layer within the window
        if var layerChange = pendingChanges[id] {
            layerChange.aspects.insert(aspect)
            pendingChanges[id] = layerChange
        } else {
            pendingChanges[id] = CALayerChange(layer: .init(layer), aspects: aspect)
        }

        scheduleDeliveryIfNeeded()
    }

    private func scheduleDeliveryIfNeeded() {
        let now = timerScheduler.now

        // This should not happen with the current start()/stop() semantics, it is purely defensive.
        guard let last = lastDeliveryTime else {
            lastDeliveryTime = now
            scheduleDelivery(after: minimumDeliveryInterval)
            return
        }

        let elapsed = now - last

        // If the window elapsed, deliver immediately. Otherwise schedule a one-shot
        // delivery for the remaining time (if not already scheduled).
        if elapsed >= minimumDeliveryInterval {
            deliverPendingChanges(now)
        } else if scheduledDelivery == nil {
            scheduleDelivery(after: minimumDeliveryInterval - elapsed)
        }
    }

    private func scheduleDelivery(after delay: TimeInterval) {
        scheduledDelivery = timerScheduler.schedule(after: delay) { [weak self] in
            guard let self else {
                return
            }

            self.scheduledDelivery = nil
            self.deliverPendingChanges(self.timerScheduler.now)
        }
    }

    private func deliverPendingChanges(_ now: TimeInterval) {
        let changes = CALayerChangeset(pendingChanges)

        pendingChanges.removeAll()
        lastDeliveryTime = now

        if !changes.isEmpty, let handler {
            handler(changes)
        }
    }
}

extension CALayerChangeAggregator: CALayerObserver {
    func layerDidDisplay(_ layer: CALayer) {
        record(layer, aspect: .display)
    }

    func layerDidDraw(_ layer: CALayer, in _: CGContext) {
        record(layer, aspect: .draw)
    }

    func layerDidLayoutSublayers(_ layer: CALayer) {
        record(layer, aspect: .layout)
    }
}
#endif
