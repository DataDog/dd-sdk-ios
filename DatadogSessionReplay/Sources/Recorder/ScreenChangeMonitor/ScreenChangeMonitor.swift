/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Observes screen changes from `CALayer` activity.
///
/// `start()` begins layer observation and delivers batched changesets through
/// `handler`. `stop()` ends observation and clears pending changes.
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
        timerScheduler: any TimerScheduler = .dispatchSource,
        screenChangeFilter: ScreenChangeFilter = ScreenChangeFilter(),
        handler: ((CALayerChangeset) -> Void)? = nil
    ) throws {
        self.layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: minimumDeliveryInterval,
            timerScheduler: timerScheduler,
            screenChangeFilter: screenChangeFilter,
            handler: handler
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
