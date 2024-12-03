/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics

/// Same heuristic as Android to determine if an image is likely bundled:
/// Icons and small assets usually have dimensions <= 100 points.
internal extension CGImage {
    func isLikelyBundled(scale: CGFloat) -> Bool {
        let pointSize = self.pointSize(scale: scale)
        let maxDimension: CGFloat = 100
        return pointSize.width <= maxDimension && pointSize.height <= maxDimension
    }

    private func pointSize(scale: CGFloat) -> CGSize {
        return CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
    }
}
#endif
