/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Coordinates observation of `CALayer` activity for screen updates. Swizzles
// `CALayer` to observe changes and aggregates them into time-windowed snapshots
// delivered via the provided handler.
//
// Call `start()` to begin observing and receiving snapshots; call
// `stop()` to end observation and clear pending state.

#if os(iOS)
import Foundation

internal final class ScreenChangeMonitor {
    private let layerChangeAggregator: CALayerChangeAggregator
    private let layerSwizzler: CALayerSwizzler

    init(
        minimumDeliveryInterval: TimeInterval,
        timerScheduler: any TimerScheduler = .dispatchSource,
        handler: @escaping (CALayerChangeSnapshot) -> Void
    ) throws {
        self.layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: minimumDeliveryInterval,
            timerScheduler: timerScheduler,
            handler: handler
        )
        self.layerSwizzler = try CALayerSwizzler(observer: layerChangeAggregator)
    }

    deinit {
        stop()
    }

    func start() {
        layerChangeAggregator.start()
        layerSwizzler.swizzle()
    }

    func stop() {
        layerSwizzler.unswizzle()
        layerChangeAggregator.stop()
    }
}
#endif
