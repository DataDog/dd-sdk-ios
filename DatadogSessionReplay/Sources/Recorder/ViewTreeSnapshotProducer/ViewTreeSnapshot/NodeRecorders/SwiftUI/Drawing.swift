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
internal struct Drawing {
    private enum Constants {
        static let cls: AnyClass? = NSClassFromString("RBMovedDisplayListContents")
        static let renderInContextOptions: Selector = NSSelectorFromString("renderInContext:options:")
        static let boundingRectKey = "boundingRect"
        static let rasterizationScaleKey = "rasterizationscale"
        static let maxSize = 1_024
    }

    private let contents: NSObject
    private let origin: CGPoint
    private let scale: CGFloat

    fileprivate var bounds: CGRect? {
        contents.value(forKey: Constants.boundingRectKey) as? CGRect
    }

    init?(contents: NSObject, origin: CGPoint, scale: CGFloat = UIScreen.main.scale) {
        guard
            let cls = Constants.cls,
            type(of: contents).isSubclass(of: cls),
            contents.responds(to: Constants.renderInContextOptions)
        else {
            return nil
        }

        self.contents = contents
        self.origin = origin
        self.scale = scale
    }

    fileprivate func render(in context: CGContext) {
        contents.perform(
            Constants.renderInContextOptions,
            with: context,
            with: [Constants.rasterizationScaleKey: scale]
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension Drawing: ImageRepresentable {
    static func == (lhs: Drawing, rhs: Drawing) -> Bool {
        lhs.contents.isEqual(rhs.contents) && lhs.origin == rhs.origin
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contents.hash)
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(scale)
    }

    func makeImage() -> UIImage? {
        guard let bounds else {
            return nil
        }

        // Compute image size
        //   - Add 0.5 pixel padding (0.5 + 0.5)
        //   - Add 0.5 pixel round-half-up
        //   - Scale

        let width = Int((bounds.width + 1.5) * scale)
        let height = Int((bounds.height + 1.5) * scale)

        guard
            width > 0, height > 0,
            width <= Constants.maxSize, height <= Constants.maxSize
        else {
            return nil
        }

        // Create a bitmap context

        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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

        // Render the contents
        render(in: bitmapContext)

        return bitmapContext.makeImage().map {
            UIImage(cgImage: $0, scale: scale, orientation: .up)
        }
    }
}

#endif
