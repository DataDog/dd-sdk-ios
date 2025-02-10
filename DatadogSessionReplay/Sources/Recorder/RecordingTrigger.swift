/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import UIKit

/// Orchestrates the process of triggering next snapshot recording.
/// It has a couple recording triggers which are done by using swizzling.
/// CALayer drawing/display; UIView layout and all UIApplication events - touches, screen rotation, etc.
internal protocol RecordingTriggering {
    func startWatchingTriggers(_ callback: @escaping () -> Void)
    func stopWatchingTriggers()
}

internal final class RecordingTrigger: RecordingTriggering, UIViewHandler, UIEventHandler, CALayerHandler {
    private var uiViewSwizzler: UIViewSwizzler? = nil
    private var uiApplicationSwizzler: UIApplicationSwizzler? = nil
    private var caLayerSwizzler: CALayerSwizzler? = nil

    private var triggerCallback: (() -> Void)?

    init() throws {
        uiViewSwizzler = try UIViewSwizzler(handler: self)
        uiApplicationSwizzler = try UIApplicationSwizzler(handler: self)
        caLayerSwizzler = try CALayerSwizzler(handler: self)
    }

    deinit {
        uiViewSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        caLayerSwizzler?.unswizzle()
    }

    func startWatchingTriggers(_ callback: @escaping () -> Void) {
        triggerCallback = callback
        uiViewSwizzler?.swizzle()
        uiApplicationSwizzler?.swizzle()
        caLayerSwizzler?.swizzle()
    }

    func stopWatchingTriggers() {
        triggerCallback = nil
        uiViewSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        caLayerSwizzler?.unswizzle()
    }

    // MARK: - CALayer Swizzling Handlers

    func notify_setNeedsDisplay(layer: CALayer) {
        triggerCallback?()
    }

    func notify_draw(layer: CALayer, context: CGContext) {
        triggerCallback?()
    }

    // MARK: - UIView Swizzling Handlers

    func notify_layoutSubviews(view: UIView) {
        triggerCallback?()
    }

    // MARK: - UIApplication Swizzling Handlers

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        triggerCallback?()
    }
}
#endif
