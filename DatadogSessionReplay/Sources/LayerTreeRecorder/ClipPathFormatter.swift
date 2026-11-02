/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import SwiftUI

/// Formats layer clipping geometry as SVG.
internal final class ClipPathFormatter: @unchecked Sendable {
    static let shared = ClipPathFormatter()

    private class Key: NSObject {
        private let size: CGSize
        private let cornerRadii: CALayerSnapshot.CornerRadii
        private let cornerCurve: CALayerCornerCurve

        init(size: CGSize, cornerRadii: CALayerSnapshot.CornerRadii, cornerCurve: CALayerCornerCurve) {
            self.size = size
            self.cornerRadii = cornerRadii
            self.cornerCurve = cornerCurve
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(size.width)
            hasher.combine(size.height)
            hasher.combine(cornerRadii.topLeft.width)
            hasher.combine(cornerRadii.topLeft.height)
            hasher.combine(cornerRadii.topRight.width)
            hasher.combine(cornerRadii.topRight.height)
            hasher.combine(cornerRadii.bottomLeft.width)
            hasher.combine(cornerRadii.bottomLeft.height)
            hasher.combine(cornerRadii.bottomRight.width)
            hasher.combine(cornerRadii.bottomRight.height)
            hasher.combine(cornerCurve)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else {
                return false
            }
            return size == other.size
                && cornerRadii == other.cornerRadii
                && cornerCurve == other.cornerCurve
        }
    }

    private let cache = NSCache<Key, NSString>()

    init() {
        // Advisory limits on the number of paths and their serialized UTF-8 bytes.
        cache.countLimit = 256
        cache.totalCostLimit = 256 * 1_024
    }

    func svgString(
        for size: CGSize,
        cornerRadii: CALayerSnapshot.CornerRadii,
        cornerCurve: CALayerCornerCurve
    ) -> String {
        let key = Key(size: size, cornerRadii: cornerRadii, cornerCurve: cornerCurve)

        if let path = cache.object(forKey: key) {
            return path as String
        }

        let path = SwiftUI.Path(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            cornerCurve: cornerCurve
        ).dd.svgString
        cache.setObject(path as NSString, forKey: key, cost: path.utf8.count)

        return path
    }
}
#endif
