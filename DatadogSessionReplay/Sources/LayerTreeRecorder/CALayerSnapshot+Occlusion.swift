/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// A Boolean value indicating whether the layer draws any content.
    var drawsContent: Bool {
        contentsClass != nil || hasBackgroundColor || hasBorder
    }

    /// A Boolean value indicating whether the layer's transform contains no rotation, skew, or perspective.
    var isAxisAligned: Bool {
        transform.m12 == 0 && transform.m21 == 0
            && transform.m13 == 0 && transform.m23 == 0
            && transform.m31 == 0 && transform.m32 == 0
            && transform.m14 == 0 && transform.m24 == 0
            && transform.m34 == 0
    }

    /// A Boolean value indicating whether the layer paints its frame as an opaque rectangle.
    var isOccluder: Bool {
        opacity == 1
            && backgroundColor?.alpha == 1
            && mask == nil
            && isAxisAligned
            && (compositingFilter == nil || compositingFilter == .normal)
            && !filters.contains(where: \.affectsOpacity)
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
        let horizontalHeight = frame.height - topInset - bottomInset

        if horizontalHeight > 0 {
            rects.append(
                CGRect(
                    x: frame.minX,
                    y: frame.minY + topInset,
                    width: frame.width,
                    height: horizontalHeight
                )
            )
        }

        let leftInset = max(topLeft.width, bottomLeft.width)
        let rightInset = max(topRight.width, bottomRight.width)
        let verticalWidth = frame.width - leftInset - rightInset

        if verticalWidth > 0 {
            rects.append(
                CGRect(
                    x: frame.minX + leftInset,
                    y: frame.minY,
                    width: verticalWidth,
                    height: frame.height
                )
            )
        }

        return rects
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    fileprivate var hasBackgroundColor: Bool {
        guard let backgroundColor else {
            return false
        }
        return backgroundColor.alpha > 0
    }

    fileprivate var hasBorder: Bool {
        guard let borderColor, borderWidth > 0 else {
            return false
        }
        return borderColor.alpha > 0
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.Filter {
    fileprivate var affectsOpacity: Bool {
        switch self {
        case .glassBackground, .colorMatrix, .unknown:
            return true
        case .gaussianBlur, .saturate, .brightness, .multiplyColor:
            return false
        }
    }
}
#endif
