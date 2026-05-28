/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerTreeOptimizer {
    /// Returns an optimized version of the given snapshot.
    func optimize(_ snapshot: LayerTreeSnapshot) -> LayerTreeSnapshot {
        LayerTreeSnapshot(
            date: snapshot.date,
            context: snapshot.context,
            viewportSize: snapshot.viewportSize,
            root: snapshot.root.sortedByZPosition(),
            webViewSlotIDs: snapshot.webViewSlotIDs
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    func sortedByZPosition() -> CALayerSnapshot {
        guard !sublayers.isEmpty else {
            return self
        }

        var layerSnapshot = self

        layerSnapshot.sublayers = sublayers
            .sorted { $0.zPosition < $1.zPosition }
            .map { $0.sortedByZPosition() }

        return layerSnapshot
    }
}
#endif
