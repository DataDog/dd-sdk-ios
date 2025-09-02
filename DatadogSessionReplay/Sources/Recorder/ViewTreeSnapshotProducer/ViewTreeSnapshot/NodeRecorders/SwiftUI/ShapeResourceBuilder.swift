/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

@available(iOS 13.0, *)
internal final class ShapeResourceBuilder {
    private class PathKey: NSObject {
        private let path: SwiftUI.Path

        init(_ path: Path) {
            self.path = path
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(path.description)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? PathKey else {
                return false
            }
            return path == other.path
        }
    }

    private class ResourceKey: NSObject {
        private let path: SwiftUI.Path
        private let color: ResolvedPaint
        private let fillStyle: SwiftUI.FillStyle
        private let size: CGSize

        init(
            _ path: SwiftUI.Path,
            _ color: ResolvedPaint,
            _ fillStyle: SwiftUI.FillStyle,
            _ size: CGSize
        ) {
            self.path = path
            self.color = color
            self.fillStyle = fillStyle
            self.size = size
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(path.description)
            hasher.combine(color)
            hasher.combine(fillStyle.isEOFilled)
            hasher.combine(size.width)
            hasher.combine(size.height)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ResourceKey else {
                return false
            }
            return path == other.path
                && color == other.color
                && fillStyle == other.fillStyle
                && size == other.size
        }
    }

    private let pathCache = NSCache<PathKey, NSString>()
    private let resourceCache = NSCache<ResourceKey, ShapeResource>()

    init() {
        pathCache.countLimit = 25
        resourceCache.countLimit = 50
    }

    func shapeResource(
        for path: SwiftUI.Path,
        color: ResolvedPaint,
        fillStyle: SwiftUI.FillStyle,
        size: CGSize
    ) -> ShapeResource {
        let key = ResourceKey(path, color, fillStyle, size)

        if let resource = resourceCache.object(forKey: key) {
            return resource
        }

        let pathData = self.pathData(for: path)
        let fillColor = color.paint.map(\.uiColor.dd.hexString) ?? "#000000FF"
        let fillRule = fillStyle.isEOFilled ? "evenodd" : "nonzero"

        let resource = ShapeResource(
            svgString: """
            <svg width="\(size.width.dd.svgString)" height="\(size.height.dd.svgString)" xmlns="http://www.w3.org/2000/svg">
              <path d="\(pathData)" fill="\(fillColor)" fill-rule="\(fillRule)"/>
            </svg>
            """
        )

        resourceCache.setObject(resource, forKey: key)

        return resource
    }

    private func pathData(for path: SwiftUI.Path) -> String {
        let key = PathKey(path)

        if let pathData = pathCache.object(forKey: key) {
            return pathData as String
        }

        let pathData = path.dd.svgString

        pathCache.setObject(pathData as NSString, forKey: key)

        return pathData
    }
}

#endif
