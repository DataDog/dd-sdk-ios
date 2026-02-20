/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Main-actor image rendering stage for layer-tree recording.
//
// The renderer receives captured snapshots, selects image candidates, and returns
// either rendered/reused layer images or timeout markers. It keeps a cache of
// rendered images and their last captured local rect to avoid unnecessary renders.
// Rendering failures are surfaced as discarded snapshots.

#if os(iOS)
import Foundation
import QuartzCore
import UIKit

@available(iOS 13.0, tvOS 13.0, *)
internal final class LayerImage: Sendable {
    let resource: UIImageResource
    let frame: CGRect

    init(resource: UIImageResource, frame: CGRect) {
        self.resource = resource
        self.frame = frame
    }
}

@available(iOS 13.0, tvOS 13.0, *)
internal enum LayerImageError: Error, Equatable {
    case timedOut
    case discarded
}

@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerImageRendering {
    func renderImages(
        for snapshots: [LayerSnapshot],
        changes: CALayerChangeset,
        rootLayer: CALayerReference,
        timeoutInterval: TimeInterval
    ) async -> [Int64: LayerImageRenderer.Result]
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal final class LayerImageRenderer: LayerImageRendering {
    private enum Constants {
        static let yieldThreshold: TimeInterval = 0.008
    }

    struct CachePolicy {
        let expirationFrameCount: UInt64
        let evictionIntervalFrameCount: UInt64
        let maximumEvictions: Int

        static let `default` = Self(
            expirationFrameCount: 300,
            evictionIntervalFrameCount: 10,
            maximumEvictions: 128
        )
    }

    typealias Result = Swift.Result<LayerImage, LayerImageError>

    private let scale: CGFloat?
    private let timeSource: any TimeSource
    private let cachePolicy: CachePolicy

    // Stores the last captured image rect in the layer local coordinate space.
    // This lets us detect when a previously partial capture no longer covers
    // the currently visible region
    private var imageRects: [Int64: CGRect] = [:]

    // Tracks when a replay ID was last observed in a captured snapshot, even if
    // it did not need image rendering in that frame
    private var frames: [Int64: UInt64] = [:]
    private var frameNumber: UInt64 = 0

    private let images = NSCache<NSNumber, LayerImage>()

    init(
        scale: CGFloat? = nil,
        timeSource: any TimeSource = .mediaTime,
        cachePolicy: CachePolicy = .default
    ) {
        self.scale = scale
        self.timeSource = timeSource
        self.cachePolicy = .init(
            expirationFrameCount: cachePolicy.expirationFrameCount,
            evictionIntervalFrameCount: max(1, cachePolicy.evictionIntervalFrameCount),
            maximumEvictions: max(1, cachePolicy.maximumEvictions)
        )
    }

    func renderImages(
        for snapshots: [LayerSnapshot],
        changes: CALayerChangeset,
        rootLayer: CALayerReference,
        timeoutInterval: TimeInterval
    ) async -> [Int64: Result] {
        frameNumber &+= 1
        setSnapshots(snapshots, atFrame: frameNumber)

        if frameNumber.isMultiple(of: cachePolicy.evictionIntervalFrameCount) {
            evictExpiredCacheEntries(atFrame: frameNumber)
        }

        let startTime = timeSource.now

        guard let rootLayer = rootLayer.resolve() else {
            return [:]
        }

        let candidates = candidates(for: snapshots, with: changes)

        guard !candidates.isEmpty else {
            return [:]
        }

        var lastYieldTime = startTime
        var results: [Int64: Result] = [:]

        results.reserveCapacity(candidates.count)

        var firstUnprocessedIndex = candidates.endIndex

        for index in candidates.indices {
            let now = timeSource.now

            // Stop rendering when the time budget is exhausted and mark the
            // remaining candidates as timed out
            if Task.isCancelled || (now - startTime) >= timeoutInterval {
                firstUnprocessedIndex = index
                break
            }

            let snapshot = candidates[index]

            if let image = renderImage(for: snapshot, changes: changes, rootLayer: rootLayer) {
                results[snapshot.replayID] = .success(image)
            } else {
                results[snapshot.replayID] = .failure(.discarded)
            }

            if now - lastYieldTime >= Constants.yieldThreshold {
                await Task.yield()
                lastYieldTime = timeSource.now
            }
        }

        if firstUnprocessedIndex < candidates.endIndex {
            for snapshot in candidates[firstUnprocessedIndex...] {
                results[snapshot.replayID] = .failure(.timedOut)
            }
        }

        return results
    }

    private func candidates(
        for snapshots: [LayerSnapshot],
        with changes: CALayerChangeset
    ) -> [LayerSnapshot] {
        snapshots.filter { snapshot in
            guard let layerClass = snapshot.layer.class else {
                removeCache(for: snapshot.replayID)
                return false
            }

            if layerClass == CALayer.self {
                // Plain layers only need image processing when they have
                // drawable contents, content changes, or a previously tracked image
                return snapshot.hasContents ||
                    changes.hasContentChanges(for: snapshot.layer) ||
                    (imageRects[snapshot.replayID] != nil)
            } else {
                // Treat all CALayer subclasses as image rendering candidates
                return true
            }
        }
    }

    private func renderImage(
        for snapshot: LayerSnapshot,
        changes: CALayerChangeset,
        rootLayer: CALayer
    ) -> LayerImage? {
        do {
            let layerImageChange = try snapshot.layerImageChange(
                with: changes,
                imageRects: imageRects,
                relativeTo: rootLayer
            )

            // If a new render is not needed and we still have the previous image,
            // reuse its resource and update frame only when needed
            if !layerImageChange.needsRender, let layerImage = images.object(forKey: snapshot.replayID as NSNumber) {
                let frame = layerImageChange.rect(in: rootLayer)

                if layerImage.frame.equalTo(frame) {
                    return layerImage
                }

                let newLayerImage = LayerImage(resource: layerImage.resource, frame: frame)
                images.setObject(newLayerImage, forKey: snapshot.replayID as NSNumber)
                return newLayerImage
            }

            let image = renderImage(
                for: layerImageChange.layer,
                in: layerImageChange.rect,
                opaque: snapshot.isOpaque
            )
            let layerImage = LayerImage(
                resource: .init(image: image, tintColor: nil),
                frame: layerImageChange.rect(in: rootLayer)
            )

            imageRects[snapshot.replayID] = layerImageChange.rect
            images.setObject(layerImage, forKey: snapshot.replayID as NSNumber)

            return layerImage
        } catch LayerImageChangeError.missingLayer {
            removeCache(for: snapshot.replayID)
            return nil
        } catch {
            // Rendering errors are mapped to discarded snapshots by the caller.
            return nil
        }
    }

    private func setSnapshots(_ snapshots: [LayerSnapshot], atFrame frame: UInt64) {
        for snapshot in snapshots {
            frames[snapshot.replayID] = frame
        }
    }

    private func evictExpiredCacheEntries(atFrame currentFrame: UInt64) {
        var evictedCount = 0

        for (replayID, lastSeen) in frames where currentFrame - lastSeen > cachePolicy.expirationFrameCount {
            removeCache(for: replayID)
            evictedCount += 1

            if evictedCount == cachePolicy.maximumEvictions {
                break
            }
        }
    }

    private func removeCache(for replayID: Int64) {
        imageRects.removeValue(forKey: replayID)
        frames.removeValue(forKey: replayID)
        images.removeObject(forKey: replayID as NSNumber)
    }

    private func renderImage(for layer: CALayer, in rect: CGRect, opaque: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale ?? layer.contentsScale
        format.opaque = opaque

        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return renderer.image { context in
            // Render only the requested local rect by translating the context.
            context.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            layer.render(in: context.cgContext)
        }
    }
}
#endif
