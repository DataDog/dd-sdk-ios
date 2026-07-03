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
    /// Radius values for each layer corner.
    struct CornerRadii: Sendable, Equatable {
        static let zero = CornerRadii()

        var topLeft: CGSize
        var topRight: CGSize
        var bottomLeft: CGSize
        var bottomRight: CGSize

        init(
            topLeft: CGSize = .zero,
            topRight: CGSize = .zero,
            bottomLeft: CGSize = .zero,
            bottomRight: CGSize = .zero
        ) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }

        init(cornerRadius: CGFloat, maskedCorners: CACornerMask) {
            let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
            self.init(
                topLeft: maskedCorners.contains(.layerMinXMinYCorner) ? cornerSize : .zero,
                topRight: maskedCorners.contains(.layerMaxXMinYCorner) ? cornerSize : .zero,
                bottomLeft: maskedCorners.contains(.layerMinXMaxYCorner) ? cornerSize : .zero,
                bottomRight: maskedCorners.contains(.layerMaxXMaxYCorner) ? cornerSize : .zero
            )
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.CornerRadii {
    var uniformCornerRadius: CGFloat? {
        guard
            topLeft.width == topLeft.height,
            topLeft == topRight,
            topRight == bottomLeft,
            bottomLeft == bottomRight
        else {
            return nil
        }
        return topLeft.width
    }
}
#endif
