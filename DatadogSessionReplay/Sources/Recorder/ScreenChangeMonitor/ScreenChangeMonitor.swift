/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Coordinates observation of `CALayer` activity for screen updates. Swizzles
// `CALayer` to observe changes and aggregates them into time-windowed changesets
// delivered via the provided handler.
//
// Call `start()` to begin observing and receiving changesets; call
// `stop()` to end observation and clear pending state.

#if os(iOS)
import Foundation

internal final class ScreenChangeMonitor {
    var handler: ((CALayerChangeset) -> Void)? {
        get { layerChangeAggregator.handler }
        set { layerChangeAggregator.handler = newValue }
    }

    private let layerChangeAggregator: CALayerChangeAggregator
    private let layerSwizzler: CALayerSwizzler
    private var isRunning = false

    init(
        minimumDeliveryInterval: TimeInterval,
        timerScheduler: any TimerScheduler = .dispatchSource
    ) throws {
        self.layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: minimumDeliveryInterval,
            timerScheduler: timerScheduler
        )
        self.layerSwizzler = try CALayerSwizzler(observer: layerChangeAggregator)
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else {
            return
        }

        layerChangeAggregator.start()
        layerSwizzler.swizzle()

        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        layerSwizzler.unswizzle()
        layerChangeAggregator.stop()

        isRunning = false
    }
}
#endif
