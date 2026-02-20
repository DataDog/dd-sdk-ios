/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Rendering decision helpers for layer snapshots.
//
// This stage derives a per-snapshot image change from current layer state,
// accumulated change signals, and the previously captured image rect. It
// decides whether a new image render is required and which local rect to render.

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerImageChange {
    let layer: CALayer
    let rect: CGRect
    let needsRender: Bool

    func rect(in other: CALayer) -> CGRect {
        layer.convert(rect, to: other)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
internal enum LayerImageChangeError: Error {
    case missingLayer
    case invalidRect
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    @MainActor
    func layerImageChange(
        with changes: CALayerChangeset,
        imageRects: [Int64: CGRect],
        relativeTo rootLayer: CALayer
    ) throws -> LayerImageChange {
        guard let layer = layer.resolve() else {
            throw LayerImageChangeError.missingLayer
        }

        // Convert the snapshot visible region from root coordinates to layer local
        // coordinates, which are used for partial image rendering
        let visibleRect = layer.convert(frame.intersection(clipRect), from: rootLayer)

        guard !visibleRect.isNull, !visibleRect.isEmpty else {
            throw LayerImageChangeError.invalidRect
        }

        let hasContentChanges = changes.hasContentChanges(for: self.layer)
        let lastImageRect = imageRects[replayID]
        let isNew = lastImageRect == nil

        let lastRenderWasPartial = lastImageRect.map { rect in
            !rect.equalTo(layer.bounds)
        } ?? false
        let renderWillBePartial = layer.bounds.sizeExceeds(rootLayer.bounds)
        let isPartialImage = lastRenderWasPartial || (isNew && renderWillBePartial)
        // Partial captures are content-addressed by local visible rect
        // Any rect change requires a re-render to keep the rendered pixels aligned
        let imageRectDidChange = isPartialImage && !(lastImageRect?.equalTo(visibleRect) ?? false)

        // Determine when pixel content may have changed
        let needsRender = if type(of: layer) == CALayer.self {
            // For plain CALayer this means first appearance with layer contents, explicit
            // content changes, or partial coverage changes
            (hasContents && isNew) || hasContentChanges || imageRectDidChange
        } else {
            // For CALayer subclasses this means first appearance, content changes, visual animations,
            // or partial coverage changes
            isNew || hasContentChanges || layer.hasVisualAnimation || imageRectDidChange
        }

        return LayerImageChange(
            layer: layer,
            // For oversized layers, render only the visible local rect
            rect: renderWillBePartial ? visibleRect : layer.bounds,
            needsRender: needsRender
        )
    }
}

extension CALayer {
    private enum Constants {
        static let geometryKeys: Set<String> = [
            "position",
            "position.x",
            "position.y",
            "zPosition",
            "anchorPoint",
            "anchorPoint.x",
            "anchorPoint.y"
        ]
    }

    fileprivate var hasVisualAnimation: Bool {
        guard let animationKeys = self.animationKeys(), !animationKeys.isEmpty else {
            return false
        }

        // Ignore pure geometry animations as they can be represented by frame updates
        return animationKeys.contains {
            !Constants.geometryKeys.contains($0)
        }
    }
}

extension CGRect {
    fileprivate func sizeExceeds(_ other: CGRect) -> Bool {
        width > other.width || height > other.height
    }
}
#endif
