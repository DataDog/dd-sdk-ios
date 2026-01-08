/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Aggregates observed `CALayer` changes over time and delivers snapshots at a
// minimum interval. Records which aspects changed per layer and invokes a
// handler with a `CALayerChangeSnapshot` for batching, correlation, and reporting.

#if os(iOS)
import QuartzCore

internal final class CALayerChangeAggregator<T: TimeProvider> {
    private let minimumDeliveryInterval: TimeInterval
    private let timeProvider: T
    private let handler: (CALayerChangeSnapshot) -> Void

    private var isRunning = false
    private var pendingChanges: [ObjectIdentifier: CALayerChange] = [:]
    private var lastDeliveryTime: TimeInterval?
    private var scheduledDelivery: T.Task?

    init(
        minimumDeliveryInterval: TimeInterval,
        timeProvider: T,
        handler: @escaping (CALayerChangeSnapshot) -> Void
    ) {
        self.minimumDeliveryInterval = minimumDeliveryInterval
        self.timeProvider = timeProvider
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
        lastDeliveryTime = timeProvider.now
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
            pendingChanges[id] = CALayerChange(layer: layer, aspects: aspect)
        }

        scheduleDeliveryIfNeeded()
    }

    private func scheduleDeliveryIfNeeded() {
        let now = timeProvider.now

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
        scheduledDelivery = timeProvider.schedule(after: delay) { [weak self] in
            guard let self else {
                return
            }

            self.scheduledDelivery = nil
            self.deliverPendingChanges(self.timeProvider.now)
        }
    }

    private func deliverPendingChanges(_ now: TimeInterval) {
        let snapshot = CALayerChangeSnapshot(pendingChanges)
            .removingDeallocatedLayers()

        pendingChanges.removeAll()
        lastDeliveryTime = now

        if !snapshot.isEmpty {
            handler(snapshot)
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
