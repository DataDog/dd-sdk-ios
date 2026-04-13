/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Coordinates observation of `CALayer` activity for screen updates.
//
// The swizzler reports layer changes to the aggregator. A timer drains
// the aggregator and delivers snapshots to the handler.

#if os(iOS)
import Foundation

internal final class ScreenChangeMonitor {
    private let layerChangeAggregator: CALayerChangeAggregator
    private let layerSwizzler: CALayerSwizzler
    private let timer: any RepeatingTimer
    private let interval: TimeInterval
    private let handler: (CALayerChangeSnapshot) -> Void

    init(
        minimumDeliveryInterval: TimeInterval,
        timer: any RepeatingTimer = .dispatchSource,
        handler: @escaping (CALayerChangeSnapshot) -> Void
    ) throws {
        self.layerChangeAggregator = CALayerChangeAggregator()
        self.layerSwizzler = try CALayerSwizzler(observer: layerChangeAggregator)
        self.timer = timer
        self.interval = minimumDeliveryInterval
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        layerSwizzler.swizzle()
        timer.start(interval: interval) { [weak self] in
            self?.deliverPendingChanges()
        }
    }

    func stop() {
        timer.stop()
        layerSwizzler.unswizzle()
    }

    private func deliverPendingChanges() {
        let snapshot = layerChangeAggregator.takePendingChanges()
        if !snapshot.isEmpty {
            handler(snapshot)
        }
    }
}
#endif
