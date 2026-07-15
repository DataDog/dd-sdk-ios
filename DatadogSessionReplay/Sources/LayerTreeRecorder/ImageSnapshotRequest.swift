/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@preconcurrency import DatadogInternal

/// Request to render one layer bitmap.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageSnapshotRequest: Sendable {
    case content(ContentSnapshotRequest)
    case mask(MaskSnapshotRequest)

    var replayID: Int64 {
        switch self {
        case .content(let request):
            return request.replayID
        case .mask(let request):
            return request.replayID
        }
    }

    var hasChanges: Bool {
        switch self {
        case .content(let request):
            return request.hasChanges
        case .mask(let request):
            return request.hasChanges
        }
    }
}

/// Request to render one `CALayerSnapshot` as a content image.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ContentSnapshotRequest: Sendable {
    let replayID: Int64
    let layer: CALayerReference
    let layerClass: AnyClass
    let delegateClass: AnyClass?
    let hasLayerSemantics: Bool
    let bounds: CGRect
    let absoluteFrame: CGRect
    let visibleFrame: CGRect
    let isOpaque: Bool
    let hasContents: Bool
    let dependencies: [CALayerReference]
    let hasChanges: Bool
    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel
    let previousSnapshotData: ContentSnapshotData?

    init(
        replayID: Int64,
        layer: CALayerReference,
        layerClass: AnyClass,
        delegateClass: AnyClass?,
        hasLayerSemantics: Bool,
        bounds: CGRect,
        absoluteFrame: CGRect,
        visibleFrame: CGRect,
        isOpaque: Bool,
        hasContents: Bool,
        dependencies: [CALayerReference],
        hasChanges: Bool,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel,
        previousSnapshotData: ContentSnapshotData?
    ) {
        self.replayID = replayID
        self.layer = layer
        self.layerClass = layerClass
        self.delegateClass = delegateClass
        self.hasLayerSemantics = hasLayerSemantics
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
internal struct ResolvedContentSnapshotRequest {
    let layer: CALayer
    let localRect: CGRect
    let frame: CGRect
    let needsSnapshot: Bool
}

/// Request to render one layer mask as an image.
@available(iOS 13.0, tvOS 13.0, *)
internal struct MaskSnapshotRequest: Sendable {
    let replayID: Int64
    let layer: CALayerReference

    /// The owner layer bounds used to render the mask, not the mask layer bounds.
    /// Some masks draw through sublayers even when the mask root has empty bounds.
    let bounds: CGRect

    let frame: CGRect
    let dependencies: [CALayerReference]
    let hasChanges: Bool
    let previousSnapshotData: MaskSnapshotData?

    init(
        replayID: Int64,
        layer: CALayerReference,
        bounds: CGRect,
        frame: CGRect,
        dependencies: [CALayerReference],
        hasChanges: Bool,
        previousSnapshotData: MaskSnapshotData?
    ) {
        self.replayID = replayID
        self.layer = layer
        self.bounds = bounds
        self.frame = frame
        self.dependencies = dependencies
        self.hasChanges = hasChanges
        self.previousSnapshotData = previousSnapshotData
    }
}

/// A mask snapshot request resolved against the current layer tree.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ResolvedMaskSnapshotRequest {
    let layer: CALayer
    let bounds: CGRect
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
extension ContentSnapshotRequest {
    @MainActor
    func resolved(relativeTo rootLayer: CALayer) throws -> ResolvedContentSnapshotRequest {
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
extension MaskSnapshotRequest {
    @MainActor
    func resolved() throws -> ResolvedMaskSnapshotRequest {
        guard let layer = layer.resolve() else {
            throw ImageSnapshotRequestResolutionError.missingLayer
        }

        guard !bounds.isNull, !bounds.isEmpty else {
            throw ImageSnapshotRequestResolutionError.invalidRect
        }

        let snapshotBoundsDidChange = previousSnapshotData.map { !$0.bounds.equalTo(bounds) } ?? false
        let snapshotFrameDidChange = previousSnapshotData.map { !$0.frame.equalTo(frame) } ?? false
        let needsSnapshot = previousSnapshotData == nil || hasChanges || snapshotBoundsDidChange || snapshotFrameDidChange

        return .init(
            layer: layer,
            bounds: bounds,
            frame: frame,
            needsSnapshot: needsSnapshot
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ContentSnapshotData {
    fileprivate var isPartial: Bool {
        !bounds.equalTo(localRect)
    }
}
#endif
