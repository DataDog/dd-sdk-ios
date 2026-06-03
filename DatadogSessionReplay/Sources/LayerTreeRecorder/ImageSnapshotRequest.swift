/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@preconcurrency import DatadogInternal

/// Request to render one `CALayerSnapshot` as an image.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ImageSnapshotRequest: Sendable {
    let replayID: Int64
    let layer: CALayerReference
    let layerClass: AnyClass
    let bounds: CGRect
    let absoluteFrame: CGRect
    let visibleFrame: CGRect
    let isOpaque: Bool
    let hasContents: Bool
    let hasContentChanges: Bool
    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel
    let previousSnapshotData: ImageSnapshotData?

    init(
        replayID: Int64,
        layer: CALayerReference,
        layerClass: AnyClass,
        bounds: CGRect,
        absoluteFrame: CGRect,
        visibleFrame: CGRect,
        isOpaque: Bool,
        hasContents: Bool,
        hasContentChanges: Bool,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel,
        previousSnapshotData: ImageSnapshotData?
    ) {
        self.replayID = replayID
        self.layer = layer
        self.layerClass = layerClass
        self.bounds = bounds
        self.absoluteFrame = absoluteFrame
        self.visibleFrame = visibleFrame
        self.isOpaque = isOpaque
        self.hasContents = hasContents
        self.hasContentChanges = hasContentChanges
        self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
        self.imagePrivacyLevel = imagePrivacyLevel
        self.previousSnapshotData = previousSnapshotData
    }
}

/// An image snapshot request resolved against the current layer tree.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ResolvedImageSnapshotRequest {
    let layer: CALayer
    let localRect: CGRect
    let frame: CGRect
    let needsSnapshot: Bool
}

/// Failure reason for resolving an image snapshot request.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageSnapshotRequestResolutionError: Error {
    case missingLayer
    case invalidRect
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshotRequest {
    @MainActor
    func resolved(relativeTo rootLayer: CALayer) throws -> ResolvedImageSnapshotRequest {
        guard let layer = layer.resolve() else {
            throw ImageSnapshotRequestResolutionError.missingLayer
        }

        let visibleLocalRect = layer.convert(visibleFrame, from: rootLayer)

        guard !visibleLocalRect.isNull, !visibleLocalRect.isEmpty else {
            throw ImageSnapshotRequestResolutionError.invalidRect
        }

        let isNew = previousSnapshotData == nil
        let lastSnapshotWasPartial = previousSnapshotData.map { !$0.bounds.equalTo($0.localRect) } ?? false
        let snapshotWillBePartial = bounds.sizeExceeds(rootLayer.bounds)
        let snapshotRectDidChange = (lastSnapshotWasPartial || snapshotWillBePartial) &&
            !(previousSnapshotData?.localRect.equalTo(visibleLocalRect) ?? false)
        let snapshotBoundsDidChange = previousSnapshotData.map { !$0.bounds.equalTo(bounds) } ?? false

        let needsSnapshot = if layerClass == CALayer.self {
            (hasContents && isNew) || hasContentChanges || snapshotRectDidChange || snapshotBoundsDidChange
        } else {
            isNew || hasContentChanges || layer.hasVisualAnimation || snapshotRectDidChange || snapshotBoundsDidChange
        }

        let localRect = snapshotWillBePartial ? visibleLocalRect : bounds

        return .init(
            layer: layer,
            localRect: localRect,
            frame: layer.convert(localRect, to: rootLayer),
            needsSnapshot: needsSnapshot
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
        guard let animationKeys = animationKeys(), !animationKeys.isEmpty else {
            return false
        }

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
