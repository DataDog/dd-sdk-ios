/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import WebKit

/// Snapshot of a layer tree and the recording context used to capture it.
@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerTreeSnapshot: Sendable {
    let date: Date
    let context: LayerRecordingContext
    let viewportSize: CGSize
    let root: CALayerSnapshot
    let webViewSlotIDs: Set<Int>
}

/// Creates layer tree snapshots on the main actor.
@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal protocol LayerTreeSnapshotBuilding: AnyObject {
    func createSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot?
}

/// Builds immutable snapshots from the current root layer.
@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal final class LayerTreeSnapshotBuilder: LayerTreeSnapshotBuilding {
    private let layerProvider: any CALayerProvider
    private let webViewCache: NSHashTable<WKWebView> = .weakObjects()

    init(layerProvider: any CALayerProvider) {
        self.layerProvider = layerProvider
    }

    func createSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot? {
        guard let rootLayer = layerProvider.rootLayer else {
            return nil
        }

        let snapshotContext = CALayerSnapshot.Context(
            textAndInputPrivacyLevel: context.textAndInputPrivacy,
            imagePrivacyLevel: context.imagePrivacy,
            webViewCache: webViewCache
        )

        guard let root = CALayerSnapshot(from: rootLayer, in: snapshotContext) else {
            return nil
        }

        return LayerTreeSnapshot(
            date: context.date.addingTimeInterval(context.viewServerTimeOffset ?? 0),
            context: context,
            viewportSize: rootLayer.bounds.size,
            root: root,
            webViewSlotIDs: Set(webViewCache.allObjects.map(\.hash))
        )
    }
}
#endif
