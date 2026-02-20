/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import WebKit

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerTreeSnapshot: Sendable {
    let date: Date
    let context: LayerRecordingContext
    let viewportSize: CGSize
    let root: LayerSnapshot
    let webViewSlotIDs: Set<Int>
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal protocol LayerTreeSnapshotBuilding: AnyObject {
    func createSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot?
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal final class LayerTreeSnapshotBuilder: LayerTreeSnapshotBuilding {
    private let layerProvider: any LayerProvider
    private let webViewCache: NSHashTable<WKWebView> = .weakObjects()

    init(layerProvider: any LayerProvider) {
        self.layerProvider = layerProvider
    }

    func createSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot? {
        guard let rootLayer = layerProvider.rootLayer else {
            return nil
        }

        let snapshotContext = LayerSnapshotContext(webViewCache: webViewCache)
        let snapshot = LayerSnapshot(from: rootLayer, in: snapshotContext)

        return LayerTreeSnapshot(
            date: context.date.addingTimeInterval(context.viewServerTimeOffset ?? 0),
            context: context,
            viewportSize: rootLayer.bounds.size,
            root: snapshot,
            webViewSlotIDs: Set(webViewCache.allObjects.map(\.hash))
        )
    }
}
#endif
