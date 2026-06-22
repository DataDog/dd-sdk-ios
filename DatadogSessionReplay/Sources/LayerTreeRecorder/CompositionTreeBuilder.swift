/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Builds the composition tree produced by the layer recording pipeline.
@available(iOS 13.0, tvOS 13.0, *)
internal class CompositionTreeBuilder {
    struct Output {
        let compositionTree: SRCompositionTree
        let wireframes: [SRWireframe]
        let resources: [Resource]
    }

    private let root: CALayerSnapshot
    private let imageSnapshotResults: [Int64: ImageSnapshotResult]
    private let webViewSlotIDs: Set<Int>

    private var layers: [SRCompositionLayer] = []
    private var wireframes: [SRWireframe] = []
    private var resources: [Resource] = []
    private var pendingWebViewSlotIDs: Set<Int> = []

    init(
        root: CALayerSnapshot,
        webViewSlotIDs: Set<Int>,
        imageSnapshotResults: [Int64: ImageSnapshotResult]
    ) {
        self.root = root
        self.webViewSlotIDs = webViewSlotIDs
        self.imageSnapshotResults = imageSnapshotResults
    }

    func build() -> Output {
        layers.removeAll(keepingCapacity: true)
        wireframes.removeAll(keepingCapacity: true)
        resources.removeAll(keepingCapacity: true)
        pendingWebViewSlotIDs = webViewSlotIDs

        let rootLayer = makeCompositionLayer(from: root)

        return Output(
            compositionTree: SRCompositionTree(
                layers: layers,
                root: rootLayer
            ),
            wireframes: makeHiddenWebViewWireframes() + wireframes,
            resources: resources
        )
    }

    private func makeCompositionLayer(from snapshot: CALayerSnapshot) -> SRCompositionLayer {
        SRCompositionLayer(
            children: children(for: snapshot),
            compositeOperation: snapshot.compositingFilter
                .flatMap(SRCompositionLayer.CompositeOperation.init(compositingFilter:)),
            height: Int64.ddWithNoOverflow(snapshot.absoluteFrame.height),
            id: snapshot.replayID,
            modifiers: snapshot.modifiers(),
            width: Int64.ddWithNoOverflow(snapshot.absoluteFrame.width),
            x: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minX),
            y: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minY)
        )
    }

    private func children(for snapshot: CALayerSnapshot) -> [SRCompositionLayerChild] {
        guard !snapshot.sublayers.isEmpty else {
            return makeWireframeReference(for: snapshot)
                .map { [$0] } ?? []
        }

        var children: [SRCompositionLayerChild] = []

        // Append a wireframe for the layer background color
        // We don't support containers with image or custom content because `CALayer.render(in:)`
        // renders both the layer and its sublayers
        if snapshot.hasBackgroundColor || snapshot.hasBorder,
           let backgroundWireframe = makeWireframeReference(for: snapshot) {
            children.append(backgroundWireframe)
        }

        children.append(
            contentsOf: snapshot.sublayers.compactMap { sublayer in
                childReference(for: sublayer)
            }
        )

        return children
    }

    private func childReference(for snapshot: CALayerSnapshot) -> SRCompositionLayerChild? {
        guard !snapshot.sublayers.isEmpty || snapshot.requiresCompositionLayer else {
            return makeWireframeReference(for: snapshot)
        }

        let layer = makeCompositionLayer(from: snapshot)
        layers.append(layer)

        return .init(id: layer.id, type: .layer)
    }

    private func makeWireframeReference(for snapshot: CALayerSnapshot) -> SRCompositionLayerChild? {
        // TBD
        nil
    }

    private func makeHiddenWebViewWireframes() -> [SRWireframe] {
        let result = pendingWebViewSlotIDs.map(SRWireframe.init(hiddenWebViewSlotID:))
        pendingWebViewSlotIDs.removeAll()
        return result
    }
}

extension SRWireframe {
    fileprivate init(hiddenWebViewSlotID slotID: Int) {
        self = .webviewWireframe(
            value: .init(
                height: 0,
                id: Int64(slotID),
                isVisible: false,
                slotId: String(slotID),
                width: 0,
                x: 0,
                y: 0
            )
        )
    }
}
#endif
