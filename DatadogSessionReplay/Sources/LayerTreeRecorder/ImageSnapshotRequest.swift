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
    let geometry: CALayerSnapshot.ContentGeometry
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
        geometry: CALayerSnapshot.ContentGeometry,
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
        self.geometry = geometry
        self.isOpaque = isOpaque
        self.hasContents = hasContents
        self.dependencies = dependencies
        self.hasChanges = hasChanges
        self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
        self.imagePrivacyLevel = imagePrivacyLevel
        self.previousSnapshotData = previousSnapshotData
    }
}

/// A content snapshot request with its live layer resolved for rendering.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ResolvedContentSnapshotRequest {
    let layer: CALayer
    let geometry: CALayerSnapshot.ContentGeometry
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
    func resolved() throws -> ResolvedContentSnapshotRequest {
        guard let layer = layer.resolve() else {
            throw ImageSnapshotRequestResolutionError.missingLayer
        }

        guard !geometry.localRect.isNull, !geometry.localRect.isEmpty else {
            throw ImageSnapshotRequestResolutionError.invalidRect
        }

        // Bounds changes invalidate the bitmap coordinate space
        let snapshotBoundsDidChange = previousSnapshotData.map { !$0.bounds.equalTo(bounds) } ?? false
        let isNewSnapshot = previousSnapshotData == nil

        // Full snapshots can be moved without re-rendering, but partial snapshots
        // depend on the visible slice captured for this frame
        let partialSnapshotHasChanges = hasPartialSnapshotChanges()

        let renderBoundsDidChange = previousSnapshotData.map {
            !$0.renderBounds.equalTo(geometry.renderBounds)
        } ?? false

        // Plain layers need contents or collapsed dependencies to produce pixels on first capture
        let shouldCaptureInitialSnapshot = layerClass != CALayer.self || hasContents || !dependencies.isEmpty

        // Render when there is no reusable snapshot or when tracked inputs changed
        let needsSnapshot = (isNewSnapshot && shouldCaptureInitialSnapshot) ||
            hasChanges ||
            partialSnapshotHasChanges ||
            snapshotBoundsDidChange ||
            renderBoundsDidChange

        return .init(
            layer: layer,
            geometry: geometry,
            needsSnapshot: needsSnapshot
        )
    }

    private func hasPartialSnapshotChanges() -> Bool {
        guard previousSnapshotData?.isPartial == true || geometry.isPartial else {
            return false
        }

        guard let previousSnapshotData else {
            return true
        }

        return !previousSnapshotData.localRect.equalTo(geometry.localRect)
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
        !renderBounds.equalTo(localRect)
    }
}
#endif
