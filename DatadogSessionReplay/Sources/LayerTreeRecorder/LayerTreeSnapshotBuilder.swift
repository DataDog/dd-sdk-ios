/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import WebKit

@_spi(Internal)
import DatadogInternal

/// Snapshot of a layer tree and the recording context used to capture it.
@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerTreeSnapshot: Sendable {
    let date: Date
    let context: LayerRecordingContext
    let viewportSize: CGSize
    var root: CALayerSnapshot
    let webViewSlotIDs: Set<Int>
    let embeddedContentSlots: [Int64: String]
}

/// Creates layer tree snapshots on the main actor.
@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal protocol LayerTreeSnapshotBuilding: AnyObject {
    func takeSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot?
}

/// Builds immutable snapshots from the current root layer.
@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal final class LayerTreeSnapshotBuilder: LayerTreeSnapshotBuilding {
    private let layerProvider: any LayerProvider
    private let webViewCache: NSHashTable<WKWebView> = .weakObjects()
    private let embeddedContentViewCache: NSHashTable<UIView> = .weakObjects()

    init(layerProvider: any LayerProvider) {
        self.layerProvider = layerProvider
    }

    func takeSnapshot(context: LayerRecordingContext) -> LayerTreeSnapshot? {
        guard let rootLayer = layerProvider.rootLayer else {
            return nil
        }

        let snapshotContext = CALayerSnapshot.Context(
            textAndInputPrivacyLevel: context.textAndInputPrivacy,
            imagePrivacyLevel: context.imagePrivacy,
            webViewCache: webViewCache,
            embeddedContentViewCache: embeddedContentViewCache
        )

        guard let root = CALayerSnapshot(from: rootLayer, in: snapshotContext) else {
            return nil
        }

        return LayerTreeSnapshot(
            date: context.date.addingTimeInterval(context.viewServerTimeOffset ?? 0),
            context: context,
            viewportSize: rootLayer.bounds.size,
            root: root,
            webViewSlotIDs: Set(webViewCache.allObjects.map(\.hash)),
            embeddedContentSlots: Dictionary(
                embeddedContentViewCache
                    .allObjects
                    .compactMap(\.embeddedContentSlot),
                uniquingKeysWith: { existing, _ in existing }
            )
        )
    }
}

extension UIView {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate var embeddedContentSlot: (Int64, String)? {
        self.dd.sessionReplaySlotID.map {
            (self.layer.replayID, $0)
        }
    }
}
#endif
