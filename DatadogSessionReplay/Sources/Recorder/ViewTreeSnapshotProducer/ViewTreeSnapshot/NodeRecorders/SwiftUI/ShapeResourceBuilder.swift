/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

/// A performance-optimized builder for creating SVG-based shape resources from SwiftUI paths.
///
/// `ShapeResourceBuilder` implements a multi-level caching strategy to eliminate expensive
/// recomputations during UI updates and scrolling animations. This addresses performance
/// issues that can occur when the same shapes are rendered repeatedly in Session Replay.
@available(iOS 13.0, *)
internal final class ShapeResourceBuilder {
    /// Cache key for SwiftUI path data, used to avoid redundant SVG path string generation.
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

    /// Composite cache key for complete shape resources, incorporating all visual properties.
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

    /// Cache for SVG path data strings, preventing redundant path-to-SVG conversions.
    private let pathCache = NSCache<PathKey, NSString>()

    /// Cache for complete shape resources, avoiding full SVG generation and hashing.
    private let resourceCache = NSCache<ResourceKey, ShapeResource>()

    init() {
        pathCache.countLimit = 25
        resourceCache.countLimit = 50
    }

    /// Creates or retrieves a cached SVG-based shape resource for the given parameters.
    ///
    /// Generated SVG follows this structure:
    ///
    /// ```xml
    /// <svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
    ///   <path d="M 10 10 L 90 90 Z" fill="#FF0000FF" fill-rule="nonzero"/>
    /// </svg>
    /// ```
    ///
    /// - Parameters:
    ///   - path: The SwiftUI path defining the shape geometry
    ///   - color: Resolved paint information including color and opacity
    ///   - fillStyle: Fill style determining the fill rule (even-odd vs non-zero)
    ///   - size: The target size for the SVG viewport
    /// - Returns: A `ShapeResource` containing the complete SVG markup
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

    /// Retrieves or generates SVG path data string for the given SwiftUI path.
    ///
    /// This method provides path-level caching to avoid expensive path-to-SVG conversion
    /// when the same path geometry is used with different visual properties (colors, sizes).
    ///
    /// - Parameter path: The SwiftUI path to convert to SVG path data
    /// - Returns: SVG path data string (e.g., "M 10 10 L 90 90 Z")
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
