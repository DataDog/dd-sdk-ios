/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import CoreGraphics

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    var isOpaque: Bool {
        backgroundColor?.alpha == 1.0 && resolvedOpacity == 1.0 &&
        !hasMask && cornerRadius == 0 && isAxisAligned
    }
}

// MARK: - Overview
//
// Removes flattened layer snapshots that are fully obscured by opaque content in front.
//
// Culling runs front-to-back and keeps only layers that may still contribute visually.
// To keep the hot path efficient on dense trees, opaque coverage is tracked in a simple
// spatial index (`OpaqueFrameIndex`) using vertical bands plus a global bucket for
// large frames.

@available(iOS 13.0, tvOS 13.0, *)
extension Array where Element == LayerSnapshot {
    func removingObscured(in viewportRect: CGRect) -> [LayerSnapshot] {
        guard !isEmpty else {
            return self
        }

        guard !viewportRect.isInfinite, !viewportRect.isNull, !viewportRect.isEmpty else {
            return self
        }

        var index = OpaqueFrameIndex(viewport: viewportRect)

        return removingObscured { frame in
            index.contains(frame)
        } onVisibleOpaqueFrame: { frame in
            index.insert(frame)
        }
    }

    private func removingObscured(
        isFrameObscured: (CGRect) -> Bool,
        onVisibleOpaqueFrame: (CGRect) -> Void
    ) -> [LayerSnapshot] {
        var result: [LayerSnapshot] = []
        result.reserveCapacity(count)

        // Process front-to-back
        for snapshot in reversed() {
            let visibleFrame = snapshot.frame.intersection(snapshot.clipRect)

            guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
                result.append(snapshot)
                continue
            }

            guard !isFrameObscured(visibleFrame) else {
                continue
            }

            result.append(snapshot)

            if snapshot.isOpaque {
                onVisibleOpaqueFrame(visibleFrame)
            }
        }

        // Restore back-to-front order
        return result.reversed()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private struct OpaqueFrameIndex {
    private let viewport: CGRect
    private let bandHeight: CGFloat
    private let maxBandsPerFrame: Int
    private var frames: [CGRect] = []
    private var globalFrameIndices: [Int] = []
    private var bandFrameIndices: [[Int]]

    init(viewport: CGRect, bandHeight: CGFloat = 64, maxBandsPerFrame: Int = 8) {
        self.viewport = viewport.standardized
        self.bandHeight = max(1, bandHeight)
        self.maxBandsPerFrame = max(1, maxBandsPerFrame)

        let bandsCount = max(1, Int(ceil(self.viewport.height / self.bandHeight)))
        self.bandFrameIndices = Array(repeating: [], count: bandsCount)
    }

    mutating func insert(_ frame: CGRect) {
        guard let visibleFrame = visibleInViewport(frame) else {
            return
        }

        let frameIndex = frames.count
        frames.append(visibleFrame)

        let bandRange = bandRange(for: visibleFrame)
        let coveredBands = bandRange.upperBound - bandRange.lowerBound + 1

        if coveredBands > maxBandsPerFrame {
            globalFrameIndices.append(frameIndex)
            return
        }

        for band in bandRange {
            bandFrameIndices[band].append(frameIndex)
        }
    }

    func contains(_ frame: CGRect) -> Bool {
        guard let visibleFrame = visibleInViewport(frame) else {
            return false
        }

        // Check large frames first since they can occlude any viewport region.
        for frameIndex in globalFrameIndices where frames[frameIndex].contains(visibleFrame) {
            return true
        }

        for band in bandRange(for: visibleFrame) {
            for frameIndex in bandFrameIndices[band] where frames[frameIndex].contains(visibleFrame) {
                return true
            }
        }

        return false
    }

    private func visibleInViewport(_ frame: CGRect) -> CGRect? {
        let visibleFrame = frame.intersection(viewport)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            return nil
        }
        return visibleFrame
    }

    private func bandRange(for frame: CGRect) -> ClosedRange<Int> {
        let minBand = Int(floor((frame.minY - viewport.minY) / bandHeight))
        let maxBand = Int(floor((frame.maxY - CGFloat.ulpOfOne - viewport.minY) / bandHeight))

        let clampedMinBand = max(0, minBand)
        let clampedMaxBand = min(bandFrameIndices.count - 1, maxBand)

        return clampedMinBand...clampedMaxBand
    }
}
#endif
