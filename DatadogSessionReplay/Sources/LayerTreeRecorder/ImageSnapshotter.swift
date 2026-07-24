/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import Foundation
import QuartzCore
import UIKit

/// Captures rendered image snapshots from layer snapshot requests.
@available(iOS 13.0, tvOS 13.0, *)
internal protocol ImageSnapshotting: AnyObject {
    /// Renders images for the optimized layer tree within the given time budget.
    @MainActor
    func takeImageSnapshots(
        for root: CALayerSnapshot,
        changeset: CALayerChangeset,
        timeout: TimeInterval
    ) async -> ImageSnapshotBatch
}

/// Rendered snapshots produced by `ImageSnapshotter`.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ImageSnapshotBatch: Sendable {
    let contentSnapshots: [Int64: ContentSnapshotResult]
    let maskSnapshots: [Int64: MaskSnapshotResult]

    init(
        contentSnapshots: [Int64: ContentSnapshotResult] = [:],
        maskSnapshots: [Int64: MaskSnapshotResult] = [:]
    ) {
        self.contentSnapshots = contentSnapshots
        self.maskSnapshots = maskSnapshots
    }
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal final class ImageSnapshotter: ImageSnapshotting {
    private enum Constants {
        static let yieldThreshold: TimeInterval = 0.008
    }

    private let cache: ImageSnapshotCache
    private let screenChangeFilter: ScreenChangeFilter
    private let scale: CGFloat?
    private let timeSource: any TimeSource
    private let telemetry: any Telemetry

    init(
        cache: ImageSnapshotCache = ImageSnapshotCache(),
        screenChangeFilter: ScreenChangeFilter = ScreenChangeFilter(),
        scale: CGFloat? = nil,
        timeSource: any TimeSource = MediaTimeSource(),
        telemetry: any Telemetry = NOPTelemetry()
    ) {
        self.cache = cache
        self.screenChangeFilter = screenChangeFilter
        self.scale = scale
        self.timeSource = timeSource
        self.telemetry = telemetry
    }

    func takeImageSnapshots(
        for root: CALayerSnapshot,
        changeset: CALayerChangeset,
        timeout: TimeInterval
    ) async -> ImageSnapshotBatch {
        // Invalidate changed layers before request extraction. Occlusion pruning can
        // remove changed layers from the snapshot tree, but their cached images must not
        // be reused if they become visible again later.
        cache.removeContentSnapshotDataForChanges(in: changeset)
        cache.removeMaskSnapshotDataForChanges(in: changeset)

        let requests = root.imageSnapshotRequests(for: changeset, cache: cache)
        cache.updateFrameNumber(for: requests)

        guard !requests.isEmpty else {
            return .init()
        }

        let startTime = timeSource.now
        var lastYieldTime = startTime
        var contentSnapshots: [Int64: ContentSnapshotResult] = [:]
        var maskSnapshots: [Int64: MaskSnapshotResult] = [:]

        contentSnapshots.reserveCapacity(requests.count)
        maskSnapshots.reserveCapacity(requests.count)

        var firstUnprocessedIndex = requests.endIndex

        for index in requests.indices {
            let now = timeSource.now

            if Task.isCancelled || (now - startTime) >= timeout {
                firstUnprocessedIndex = index
                break
            }

            let request = requests[index]

            switch request {
            case .content(let request):
                contentSnapshots[request.replayID] = takeContentSnapshot(for: request)
            case .mask(let request):
                maskSnapshots[request.replayID] = takeMaskSnapshot(for: request)
            }

            if now - lastYieldTime >= Constants.yieldThreshold {
                await Task.yield()
                lastYieldTime = timeSource.now
            }
        }

        if firstUnprocessedIndex < requests.endIndex {
            for request in requests[firstUnprocessedIndex...] {
                if request.hasChanges {
                    switch request {
                    case .content:
                        cache.removeContentSnapshotData(forReplayID: request.replayID)
                    case .mask:
                        cache.removeMaskSnapshotData(forReplayID: request.replayID)
                    }
                }

                switch request {
                case .content:
                    contentSnapshots[request.replayID] = .failure(.timedOut)
                case .mask:
                    maskSnapshots[request.replayID] = .failure(.timedOut)
                }
            }
        }

        return .init(contentSnapshots: contentSnapshots, maskSnapshots: maskSnapshots)
    }

    private func takeContentSnapshot(for request: ContentSnapshotRequest) -> ContentSnapshotResult {
        do {
            let resolvedRequest = try request.resolved()
            let snapshot: ContentSnapshot

            if !resolvedRequest.needsSnapshot, let cachedSnapshot = request.previousSnapshotData?.snapshot {
                snapshot = ContentSnapshot(
                    image: cachedSnapshot.image,
                    frame: resolvedRequest.geometry.frame,
                    layerClass: request.layerClass,
                    delegateClass: request.delegateClass,
                    hasLayerSemantics: request.hasLayerSemantics,
                    textAndInputPrivacyLevel: request.textAndInputPrivacyLevel,
                    imagePrivacyLevel: request.imagePrivacyLevel
                )
            } else {
                snapshot = ContentSnapshot(
                    image: try renderImage(
                        for: resolvedRequest.layer,
                        in: resolvedRequest.geometry.localRect,
                        opaque: request.isOpaque && resolvedRequest.geometry.renderBounds.equalTo(request.bounds)
                    ),
                    frame: resolvedRequest.geometry.frame,
                    layerClass: request.layerClass,
                    delegateClass: request.delegateClass,
                    hasLayerSemantics: request.hasLayerSemantics,
                    textAndInputPrivacyLevel: request.textAndInputPrivacyLevel,
                    imagePrivacyLevel: request.imagePrivacyLevel
                )
            }

            cache.setContentSnapshotData(
                .init(
                    snapshot: snapshot,
                    localRect: resolvedRequest.geometry.localRect,
                    renderBounds: resolvedRequest.geometry.renderBounds,
                    bounds: request.bounds,
                    dependencies: request.dependencies
                ),
                forReplayID: request.replayID
            )
            return .success(snapshot)
        } catch ImageSnapshotRequestResolutionError.missingLayer {
            cache.removeContentSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch let objc as ObjcException {
            telemetry.error(
                "[SR] Failed to capture layer image snapshot due to Objective-C runtime exception",
                error: objc.error
            )
            cache.removeContentSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch {
            return .failure(.discarded)
        }
    }

    private func takeMaskSnapshot(for request: MaskSnapshotRequest) -> MaskSnapshotResult {
        do {
            let resolvedRequest = try request.resolved()
            let snapshot: MaskSnapshot

            if !resolvedRequest.needsSnapshot, let cachedSnapshot = request.previousSnapshotData?.snapshot {
                snapshot = cachedSnapshot
            } else {
                snapshot = MaskSnapshot(
                    image: try renderMaskImage(
                        for: resolvedRequest.layer,
                        in: resolvedRequest.bounds,
                        frame: resolvedRequest.frame
                    )
                )
            }

            cache.setMaskSnapshotData(
                .init(
                    snapshot: snapshot,
                    bounds: resolvedRequest.bounds,
                    frame: resolvedRequest.frame,
                    dependencies: request.dependencies
                ),
                forReplayID: request.replayID
            )
            return .success(snapshot)
        } catch ImageSnapshotRequestResolutionError.missingLayer {
            cache.removeMaskSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch let objc as ObjcException {
            telemetry.error(
                "[SR] Failed to capture layer mask snapshot due to Objective-C runtime exception",
                error: objc.error
            )
            cache.removeMaskSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch {
            return .failure(.discarded)
        }
    }

    private func renderImage(for layer: CALayer, in rect: CGRect, opaque: Bool) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = opaque

        if let scale {
            format.scale = scale
        }

        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return try screenChangeFilter.ignoringChanges {
            try objc_rethrow {
                renderer.image { context in
                    context.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
                    layer.render(in: context.cgContext)
                }
            }
        }
    }

    private func renderMaskImage(for layer: CALayer, in bounds: CGRect, frame: CGRect) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false

        if let scale {
            format.scale = scale
        }

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return try screenChangeFilter.ignoringChanges {
            try objc_rethrow {
                renderer.image { context in
                    // Render in owner coordinates.
                    // Offset masks are supported, but transformed masks are out of scope.
                    context.cgContext.translateBy(
                        x: frame.minX - bounds.minX,
                        y: frame.minY - bounds.minY
                    )
                    layer.render(in: context.cgContext)
                }
            }
        }
    }
}
#endif
