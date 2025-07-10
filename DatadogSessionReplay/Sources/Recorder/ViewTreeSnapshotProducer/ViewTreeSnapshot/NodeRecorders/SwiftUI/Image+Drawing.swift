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
    init?(drawingContents: NSObject, origin: CGPoint) {
        guard
            let cls = DrawingContents.cls,
            type(of: drawingContents).isSubclass(of: cls),
            drawingContents.responds(to: DrawingContents.renderInContext),
            let bounds = drawingContents.value(forKey: DrawingContents.bounds) as? CGRect
        else {
            return nil
        }

        // Compute image size

        let scale = UIScreen.main.scale
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

        // Create an image

        guard let cgImage = bitmapContext.makeImage() else {
            return nil
        }

        self.init(contents: .cgImage(cgImage), scale: scale, orientation: .up)
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
