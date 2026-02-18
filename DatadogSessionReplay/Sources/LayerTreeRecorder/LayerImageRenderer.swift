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
internal enum LayerImageError: Error {
    case timedOut
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

    typealias Result = Swift.Result<LayerImage, LayerImageError>

    private let scale: CGFloat?
    private let timeSource: any TimeSource

    // Stores the last captured image rect in the layer local coordinate space.
    // This lets us detect when a previously partial capture no longer covers
    // the currently visible region
    private var imageRects: [Int64: CGRect] = [:]

    private let images = NSCache<NSNumber, LayerImage>()

    init(scale: CGFloat? = nil, timeSource: any TimeSource = .mediaTime) {
        self.scale = scale
        self.timeSource = timeSource
    }

    func renderImages(
        for snapshots: [LayerSnapshot],
        changes: CALayerChangeset,
        rootLayer: CALayerReference,
        timeoutInterval: TimeInterval
    ) async -> [Int64: Result] {
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
                imageRects.removeValue(forKey: snapshot.replayID)
                images.removeObject(forKey: snapshot.replayID as NSNumber)
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
            // return the cached image directly
            if !layerImageChange.needsRender, let layerImage = images.object(forKey: snapshot.replayID as NSNumber) {
                return layerImage
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
            imageRects.removeValue(forKey: snapshot.replayID)
            images.removeObject(forKey: snapshot.replayID as NSNumber)
            return nil
        } catch {
            // Rendering errors are intentionally skipped
            return nil
        }
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
