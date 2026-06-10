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
    let dependencies: [CALayerReference]
    let hasChanges: Bool
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
        dependencies: [CALayerReference],
        hasChanges: Bool,
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
        self.dependencies = dependencies
        self.hasChanges = hasChanges
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

        let isNewSnapshot = previousSnapshotData == nil

        // Oversized layers are rendered only in their visible area
        let requiresPartialSnapshot = self.requiresPartialSnapshot(relativeTo: rootLayer)

        // Full snapshots can be moved without re-rendering, but partial snapshots depend on the visible slice
        let partialSnapshotHasChanges = self.hasPartialSnapshotChanges(
            visibleLocalRect: visibleLocalRect,
            requiresPartialSnapshot: requiresPartialSnapshot
        )

        // Bounds changes invalidate the bitmap coordinate space
        let snapshotBoundsDidChange = previousSnapshotData.map { !$0.bounds.equalTo(bounds) } ?? false

        // Plain layers need contents or collapsed dependencies to produce pixels on first capture
        let shouldCaptureInitialSnapshot = layerClass != CALayer.self || hasContents || !dependencies.isEmpty

        // Render when there is no reusable snapshot or when tracked inputs changed
        let needsSnapshot = (isNewSnapshot && shouldCaptureInitialSnapshot) ||
            hasChanges ||
            partialSnapshotHasChanges ||
            snapshotBoundsDidChange

        // Full snapshots capture the layer bounds while partial snapshots capture only the visible slice
        let localRect = requiresPartialSnapshot ? visibleLocalRect : bounds
        let frame = requiresPartialSnapshot ? visibleFrame : absoluteFrame

        return .init(
            layer: layer,
            localRect: localRect,
            frame: frame,
            needsSnapshot: needsSnapshot
        )
    }

    private func requiresPartialSnapshot(relativeTo rootLayer: CALayer) -> Bool {
        bounds.width > rootLayer.bounds.width || bounds.height > rootLayer.bounds.height
    }

    private func hasPartialSnapshotChanges(
        visibleLocalRect: CGRect,
        requiresPartialSnapshot: Bool
    ) -> Bool {
        guard previousSnapshotData?.isPartial == true || requiresPartialSnapshot else {
            return false
        }

        guard let previousSnapshotData else {
            return true
        }

        return !previousSnapshotData.localRect.equalTo(visibleLocalRect)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshotData {
    fileprivate var isPartial: Bool {
        !bounds.equalTo(localRect)
    }
}
#endif
