/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import Foundation
import UIKit

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage {
    init?(rasterizing drawingContents: NSObject, origin: CGPoint) {
        let rasterizationScale = UIScreen.main.scale

        guard let cgImage = Self.drawingRasterizer.image(
            rasterizing: drawingContents,
            origin: origin,
            scale: rasterizationScale
        ) else {
            return nil
        }

        self.init(contents: .cgImage(cgImage), scale: rasterizationScale, orientation: .up)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension GraphicsImage {
    fileprivate class DrawingRasterizer: @unchecked Sendable {
        private let cache = NSCache<NSNumber, CGImage>()
        private let lock = NSRecursiveLock()

        init() {
            cache.countLimit = 20
        }

        func image(rasterizing drawingContents: NSObject, origin: CGPoint, scale: CGFloat) -> CGImage? {
            lock.lock()
            defer { lock.unlock() }

            let imageKey = drawingContents.hashValue as NSNumber

            if let image = cache.object(forKey: imageKey) {
                return image
            }

            guard let image = CGImage.image(
                rasterizing: drawingContents,
                origin: origin,
                scale: scale
            ) else {
                return nil
            }

            cache.setObject(image, forKey: imageKey)
            return image
        }
    }

    fileprivate static let drawingRasterizer = DrawingRasterizer()
}

extension CGImage {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate static func image(rasterizing drawingContents: NSObject, origin: CGPoint, scale: CGFloat) -> CGImage? {
        guard
            let cls = DrawingContents.cls,
            type(of: drawingContents).isSubclass(of: cls),
            drawingContents.responds(to: DrawingContents.renderInContext),
            let bounds = drawingContents.value(forKey: DrawingContents.bounds) as? CGRect
        else {
            return nil
        }

        // Compute image size

        let width = Int((bounds.width + 1.5) * scale)
        let height = Int((bounds.height + 1.5) * scale)

        // Create a grayscale, alpha-only bitmap context

        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else {
            return nil
        }

        // Flip the coordinate system:
        //   - translateBy(x: 0, y: height)
        //   - scaleBy(x: 1, y: -1)
        // Apply y-origin
        //   - translateBy(x: 0, y: origin.y)
        // Apply rasterization scale:
        //   - scaleBy(x: scale, y: scale)

        bitmapContext.translateBy(x: 0, y: CGFloat(height) + origin.y)
        bitmapContext.scaleBy(x: scale, y: -scale)

        // Render the drawing contents

        drawingContents.perform(
            DrawingContents.renderInContext,
            with: bitmapContext,
            with: [DrawingContents.rasterizationScale: scale]
        )

        return bitmapContext.makeImage()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private enum DrawingContents {
    static let cls: AnyClass? = NSClassFromString("RBMovedDisplayListContents")
    static let renderInContext: Selector = NSSelectorFromString("renderInContext:options:")
    static let bounds = "boundingRect"
    static let rasterizationScale = "rasterizationscale"
}

#endif
