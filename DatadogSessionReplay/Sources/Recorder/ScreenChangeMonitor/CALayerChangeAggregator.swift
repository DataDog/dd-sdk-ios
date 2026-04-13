/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Collects `CALayer` changes reported by `CALayerSwizzler` and merges
// per-layer aspects until the monitor drains them.

#if os(iOS)
import QuartzCore

internal final class CALayerChangeAggregator: CALayerObserver {
    private var pendingChanges: [ObjectIdentifier: CALayerChange] = [:]

    private func accumulate(_ layer: CALayer, aspect: CALayerChange.Aspect.Set) {
        guard Thread.isMainThread else {
            return
        }

        let id = ObjectIdentifier(layer)

        if var layerChange = pendingChanges[id] {
            layerChange.aspects.insert(aspect)
            pendingChanges[id] = layerChange
        } else {
            pendingChanges[id] = CALayerChange(layer: layer, aspects: aspect)
        }
    }

    // Returns the accumulated changes and resets the internal state.
    func takePendingChanges() -> CALayerChangeSnapshot {
        let snapshot = CALayerChangeSnapshot(pendingChanges.filter(\.value.isValid))
        pendingChanges.removeAll(keepingCapacity: true)
        return snapshot
    }

    func layerDidDisplay(_ layer: CALayer) {
        accumulate(layer, aspect: .display)
    }

    func layerDidDraw(_ layer: CALayer, in _: CGContext) {
        accumulate(layer, aspect: .draw)
    }

    func layerDidLayoutSublayers(_ layer: CALayer) {
        accumulate(layer, aspect: .layout)
    }
}
#endif
