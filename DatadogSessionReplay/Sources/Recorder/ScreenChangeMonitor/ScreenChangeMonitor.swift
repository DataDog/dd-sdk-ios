/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

@_spi(Internal)
import DatadogInternal

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
    private let notificationCenter: NotificationCenter
    private var slotIDObserver: NSObjectProtocol?
    private var isRunning = false

    init(
        minimumDeliveryInterval: TimeInterval,
        timerScheduler: any TimerScheduler = .dispatchSource,
        screenChangeFilter: ScreenChangeFilter = ScreenChangeFilter(),
        notificationCenter: NotificationCenter = .default,
        handler: ((CALayerChangeset) -> Void)? = nil
    ) throws {
        self.notificationCenter = notificationCenter
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
        observeSlotIDChanges()
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        slotIDObserver.map(notificationCenter.removeObserver)
        slotIDObserver = nil
        layerSwizzler.unswizzle()
        layerChangeAggregator.stop()
        isRunning = false
    }

    /// Treats a view being marked as an embedded content slot as a screen change.
    ///
    /// Only `CALayer` display, draw and layout are observed, and assigning a slot ID produces none
    /// of them — yet the placeholder wireframe for that slot can only be recorded by a snapshot
    /// taken after the ID is in place. Feeding the view's layer in here makes the next changeset
    /// include it, so the placeholder is emitted promptly instead of waiting for whatever unrelated
    /// layer activity comes next. That wait is unbounded for hosts whose embedded content draws
    /// through a `CAMetalLayer` (Flutter, Unity), which triggers none of the observed callbacks.
    ///
    /// Reported as a layout change because that is what an assignment amounts to for the recorder:
    /// the view's contents are unchanged, but its representation in the wireframe tree is not.
    private func observeSlotIDChanges() {
        slotIDObserver = notificationCenter.addObserver(
            forName: .ddSessionReplaySlotIDDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let view = notification.object as? UIView else {
                return
            }
            // Hop to the main queue unconditionally: the aggregator only records there, and this
            // also guarantees we are not inside a changeset delivery (which it ignores changes
            // during). Assignments are rare — once per embedded view — so the hop costs nothing.
            DispatchQueue.main.async {
                self?.layerChangeAggregator.layerDidLayoutSublayers(view.layer)
            }
        }
    }
}
#endif
