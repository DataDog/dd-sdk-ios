/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// A Boolean value indicating whether the layer draws any content.
    var drawsContent: Bool {
        observation.ignoresSublayers
            || layerClass != CALayer.self
            || contentsClass != nil
            || hasBackgroundColor
            || hasBorder
            || hasShadow
    }

    /// A Boolean value indicating whether the layer paints its frame as an opaque rectangle.
    var isOccluder: Bool {
        opacity == 1
            && backgroundColor?.alpha == 1
            && mask == nil
            && transform.isAxisAligned
            && (compositingFilter == nil || compositingFilter == .normal)
            && (filters.isEmpty || filters.allSatisfy(\.preservesOpacity))
    }

    /// Returns a copy of the layer tree without layers fully hidden by opaque front siblings.
    func removingOccluded() -> CALayerSnapshot? {
        var occlusionMap = OcclusionMap(size: absoluteFrame.size)

        return removingOccluded(
            clip: absoluteFrame,
            preservesSublayerOcclusion: preservesSublayerOcclusion,
            into: &occlusionMap
        )
    }

    /// Returns the rectangles this layer contributes to the occlusion map.
    ///
    /// - Parameter visibleFrame: The layer's frame after clipping against ancestors.
    func occlusionRects(in visibleFrame: CGRect) -> [CGRect] {
        cornerRadii.occlusionRects(in: visibleFrame)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.CornerRadii {
    /// Returns the rectangles that cover the rounded shape, excluding the corner caps.
    ///
    /// - Parameter frame: The frame to inset against.
    func occlusionRects(in frame: CGRect) -> [CGRect] {
        if self == .zero {
            return [frame]
        }

        var rects: [CGRect] = []

        let topInset = max(topLeft.height, topRight.height)
        let bottomInset = max(bottomLeft.height, bottomRight.height)
        let contentHeight = frame.height - topInset - bottomInset

        if contentHeight > 0 {
            rects.append(
                CGRect(
                    x: frame.minX,
                    y: frame.minY + topInset,
                    width: frame.width,
                    height: contentHeight
                )
            )
        }

        let leftInset = max(topLeft.width, bottomLeft.width)
        let rightInset = max(topRight.width, bottomRight.width)
        let contentWidth = frame.width - leftInset - rightInset

        if contentWidth > 0 {
            rects.append(
                CGRect(
                    x: frame.minX + leftInset,
                    y: frame.minY,
                    width: contentWidth,
                    height: frame.height
                )
            )
        }

        return rects
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    var hasBackgroundColor: Bool {
        guard let backgroundColor else {
            return false
        }
        return backgroundColor.alpha > 0
    }

    var hasBorder: Bool {
        guard let borderColor, borderWidth > 0 else {
            return false
        }
        return borderColor.alpha > 0
    }

    var hasShadow: Bool {
        shadowOpacity > 0 && (shadowColor?.alpha ?? 0) > 0
    }

    fileprivate var preservesSublayerOcclusion: Bool {
        opacity == 1
            && mask == nil
            && transform.isAxisAligned
            && sublayerTransform.isAxisAligned
            && (compositingFilter == nil || compositingFilter == .normal)
            && (filters.isEmpty || filters.allSatisfy(\.preservesOpacity))
    }

    fileprivate func removingOccluded(
        clip: CGRect,
        preservesSublayerOcclusion: Bool,
        into occlusionMap: inout OcclusionMap
    ) -> CALayerSnapshot? {
        let visibleFrame = absoluteFrame.intersection(clip)

        guard !visibleFrame.isEmpty || !masksToBounds else {
            return nil
        }

        let clip = masksToBounds ? visibleFrame : clip
        let preservesSublayerOcclusion = preservesSublayerOcclusion
            && self.preservesSublayerOcclusion

        var visibleLayers: [CALayerSnapshot] = []

        // `sorted` is stable (SE-0372), so equal `zPosition` preserves capture sibling order
        sublayers.sorted {
            $0.zPosition < $1.zPosition
        }
        // We reverse separately to preserve the capture order on layers with equal `zPosition`
        .reversed()
        .forEach { sublayer in
            if let visibleLayer = sublayer.removingOccluded(
                clip: clip,
                preservesSublayerOcclusion: preservesSublayerOcclusion,
                into: &occlusionMap
            ) {
                visibleLayers.append(visibleLayer)
            }
        }

        if visibleLayers.isEmpty {
            guard !visibleFrame.isEmpty else {
                return nil
            }

            if drawsContent {
                if !hasShadow && occlusionMap.isCovered(visibleFrame) {
                    return nil
                }
            } else {
                return nil
            }
        }

        if preservesSublayerOcclusion && isOccluder {
            occlusionRects(in: visibleFrame).forEach {
                occlusionMap.insert($0)
            }
        }

        var result = self
        result.sublayers = visibleLayers.reversed()

        return result
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.Filter {
    fileprivate var preservesOpacity: Bool {
        switch self {
        case .saturate, .brightness:
            return true
        case .gaussianBlur(let radius) where radius == 0:
            return true
        case .multiplyColor(let color) where color.alpha == 1:
            return true
        default:
            return false
        }
    }
}
#endif
