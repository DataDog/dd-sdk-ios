/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Mapping layer snapshots to Session Replay wireframes.
//
// This builder translates layer-tree snapshot semantics plus rendered layer images
// into SR wireframes while reusing `WireframesBuilder` for SR model construction
// and resource collection.
//
// Decision rules:
// - `.webView` snapshots always produce webview wireframes.
// - Generic snapshots with rendered images produce image wireframes.
// - Timed out images produce placeholder wireframes.
// - Discarded images are skipped.
// - Generic snapshots without an image result produce shape wireframes only if
//   they have visible shape appearance (background and/or border).
// - Hidden webview slots are prepended to preserve parity with the current
//   snapshot processor behavior.

#if os(iOS)
import CoreGraphics
import DatadogInternal
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerWireframeBuilder {
    static let timedOutLabel = "Timed Out"

    func createWireframes(
        for snapshots: [LayerSnapshot],
        layerImages: [Int64: LayerImageRenderer.Result],
        webViewSlotIDs: Set<Int>
    ) -> ([SRWireframe], [Resource]) {
        let builder = WireframesBuilder(webViewSlotIDs: webViewSlotIDs)

        let wireframes = snapshots.compactMap { snapshot in
            createWireframe(for: snapshot, layerImages: layerImages, using: builder)
        }

        // Hidden webview wireframes must be emitted before regular wireframes.
        return (
            builder.hiddenWebViewWireframes() + wireframes,
            builder.resources
        )
    }

    private func createWireframe(
        for snapshot: LayerSnapshot,
        layerImages: [Int64: LayerImageRenderer.Result],
        using builder: WireframesBuilder
    ) -> SRWireframe? {
        switch snapshot.semantics {
        case .generic:
            return createGenericLayerWireframe(
                for: snapshot,
                layerImages: layerImages,
                using: builder
            )
        case .webView(let slotID):
            return builder.visibleWebViewWireframe(
                id: slotID,
                frame: snapshot.frame,
                clip: snapshot.clipRect,
                borderColor: snapshot.borderColor,
                borderWidth: snapshot.borderWidth,
                backgroundColor: snapshot.backgroundColor,
                cornerRadius: snapshot.cornerRadius,
                opacity: CGFloat(snapshot.resolvedOpacity)
            )
        }
    }

    private func createGenericLayerWireframe(
        for snapshot: LayerSnapshot,
        layerImages: [Int64: LayerImageRenderer.Result],
        using builder: WireframesBuilder
    ) -> SRWireframe? {
        if let layerImageResult = layerImages[snapshot.replayID] {
            switch layerImageResult {
            case .success(let layerImage):
                return builder.createImageWireframe(
                    id: snapshot.replayID,
                    resource: layerImage.resource,
                    frame: layerImage.frame,
                    clip: snapshot.clipRect,
                    borderColor: snapshot.borderColor,
                    borderWidth: snapshot.borderWidth,
                    backgroundColor: snapshot.backgroundColor,
                    cornerRadius: snapshot.cornerRadius,
                    opacity: CGFloat(snapshot.resolvedOpacity)
                )
            case .failure(.timedOut):
                return builder.createPlaceholderWireframe(
                    id: snapshot.replayID,
                    frame: snapshot.frame,
                    clip: snapshot.clipRect,
                    label: Self.timedOutLabel
                )
            case .failure(.discarded):
                return nil
            }
        }

        guard snapshot.hasVisibleBackgroundColor || snapshot.hasVisibleBorder else {
            return nil
        }

        return builder.createShapeWireframe(
            id: snapshot.replayID,
            frame: snapshot.frame,
            clip: snapshot.clipRect,
            borderColor: snapshot.borderColor,
            borderWidth: snapshot.borderWidth,
            backgroundColor: snapshot.backgroundColor,
            cornerRadius: snapshot.cornerRadius,
            opacity: CGFloat(snapshot.resolvedOpacity)
        )
    }
}
#endif
