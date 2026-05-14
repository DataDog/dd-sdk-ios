/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Aggregates observed `CALayer` changes over time and delivers changesets at a
// minimum interval. Records which aspects changed per layer and invokes a
// handler with a `CALayerChangeset` for batching, correlation, and reporting.

#if os(iOS)
import QuartzCore

internal final class CALayerChangeAggregator {
    var handler: ((CALayerChangeset) -> Void)?

    private let minimumDeliveryInterval: TimeInterval
    private let timerScheduler: any TimerScheduler

    private var isRunning = false
    private var isDeliveringChanges = false
    private var pendingChanges: [ObjectIdentifier: CALayerChange] = [:]
    private var lastDeliveryTime: TimeInterval?
    private var scheduledDelivery: (any ScheduledTimer)?

    init(
        minimumDeliveryInterval: TimeInterval,
        timerScheduler: any TimerScheduler,
        handler: ((CALayerChangeset) -> Void)? = nil
    ) {
        self.minimumDeliveryInterval = minimumDeliveryInterval
        self.timerScheduler = timerScheduler
        self.handler = handler
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
        // Only record on the main thread and ignore changes triggered in the delivery handler
        guard Thread.isMainThread, isRunning, !isDeliveringChanges else {
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

        guard let last = lastDeliveryTime else {
            lastDeliveryTime = now
            if scheduledDelivery == nil {
                scheduleDelivery(after: minimumDeliveryInterval)
            }
            return
        }

        // Always defer delivery off the layer callback stack. If the throttle window
        // already elapsed, schedule a zero-delay one-shot delivery. Otherwise schedule
        // for the remaining time. Keep at most one pending delivery so subsequent
        // changes are coalesced into the same changeset.

        guard scheduledDelivery == nil else {
            return
        }

        let elapsed = now - last
        let delay = max(0, minimumDeliveryInterval - elapsed)
        scheduleDelivery(after: delay)
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
        let changeset = CALayerChangeset(pendingChanges)

        pendingChanges.removeAll()
        lastDeliveryTime = now

        if !changeset.isEmpty, let handler {
            isDeliveringChanges = true
            defer {
                isDeliveringChanges = false
            }
            handler(changeset)
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
