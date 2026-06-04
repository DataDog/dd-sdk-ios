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
    ) async -> [Int64: ImageSnapshotResult]
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
    ) async -> [Int64: ImageSnapshotResult] {
        // Invalidate content changes before request extraction. Occlusion pruning can
        // remove changed layers from the snapshot tree, but their cached images must not
        // be reused if they become visible again later.
        cache.removeSnapshotDataForContentChanges(in: changeset)

        let requests = root.imageSnapshotRequests(for: changeset, cache: cache)
        cache.updateFrameNumber(for: requests.map(\.replayID))

        guard let rootLayer = root.layer.resolve(), !requests.isEmpty else {
            return [:]
        }

        let startTime = timeSource.now
        var lastYieldTime = startTime
        var results: [Int64: ImageSnapshotResult] = [:]

        results.reserveCapacity(requests.count)

        var firstUnprocessedIndex = requests.endIndex

        for index in requests.indices {
            let now = timeSource.now

            if Task.isCancelled || (now - startTime) >= timeout {
                firstUnprocessedIndex = index
                break
            }

            let request = requests[index]
            results[request.replayID] = takeImageSnapshot(for: request, rootLayer: rootLayer)

            if now - lastYieldTime >= Constants.yieldThreshold {
                await Task.yield()
                lastYieldTime = timeSource.now
            }
        }

        if firstUnprocessedIndex < requests.endIndex {
            for request in requests[firstUnprocessedIndex...] {
                if request.hasContentChanges {
                    cache.removeSnapshotData(forReplayID: request.replayID)
                }
                results[request.replayID] = .failure(.timedOut)
            }
        }

        return results
    }

    private func takeImageSnapshot(
        for request: ImageSnapshotRequest,
        rootLayer: CALayer
    ) -> ImageSnapshotResult {
        do {
            let resolvedRequest = try request.resolved(relativeTo: rootLayer)
            let snapshot: ImageSnapshot

            if !resolvedRequest.needsSnapshot, let cachedSnapshot = request.previousSnapshotData?.snapshot {
                snapshot = cachedSnapshot.frame.equalTo(resolvedRequest.frame)
                    ? cachedSnapshot
                    : ImageSnapshot(
                        image: cachedSnapshot.image,
                        frame: resolvedRequest.frame,
                        textAndInputPrivacyLevel: request.textAndInputPrivacyLevel,
                        imagePrivacyLevel: request.imagePrivacyLevel
                    )
            } else {
                snapshot = ImageSnapshot(
                    image: try renderImage(
                        for: resolvedRequest.layer,
                        in: resolvedRequest.localRect,
                        opaque: request.isOpaque
                    ),
                    frame: resolvedRequest.frame,
                    textAndInputPrivacyLevel: request.textAndInputPrivacyLevel,
                    imagePrivacyLevel: request.imagePrivacyLevel
                )
            }

            cache.setSnapshotData(
                .init(
                    snapshot: snapshot,
                    localRect: resolvedRequest.localRect,
                    bounds: request.bounds
                ),
                forReplayID: request.replayID
            )
            return .success(snapshot)
        } catch ImageSnapshotRequestResolutionError.missingLayer {
            cache.removeSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch let objc as ObjcException {
            telemetry.error(
                "[SR] Failed to capture layer image snapshot due to Objective-C runtime exception",
                error: objc.error
            )
            cache.removeSnapshotData(forReplayID: request.replayID)
            return .failure(.discarded)
        } catch {
            return .failure(.discarded)
        }
    }

    private func renderImage(for layer: CALayer, in rect: CGRect, opaque: Bool) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale ?? layer.contentsScale
        format.opaque = opaque

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
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshotCache {
    @MainActor
    fileprivate func removeSnapshotDataForContentChanges(in changeset: CALayerChangeset) {
        let contentChangeReplayIDs = changeset.contentChanges.compactMap {
            $0.layer.resolve()?.replayID
        }
        removeSnapshotData(forReplayIDs: Set(contentChangeReplayIDs))
    }
}
#endif
