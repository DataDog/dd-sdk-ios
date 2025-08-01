/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import CoreGraphics
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageRenderer {
    private class Key: NSObject {
        private struct Wrapped: Hashable {
            let contents: DisplayListContents
            let origin: CGPoint
            let scale: CGFloat
        }

        private let wrappedValue: Wrapped

        init(contents: DisplayListContents, origin: CGPoint, scale: CGFloat) {
            self.wrappedValue = .init(contents: contents, origin: origin, scale: scale)
        }

        override var hash: Int {
            wrappedValue.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else {
                return false
            }
            return wrappedValue == other.wrappedValue
        }
    }

    private let cache = NSCache<Key, CGImage>()

    init() {
        cache.countLimit = 20
    }

    func image(with contents: DisplayListContents, origin: CGPoint, scale: CGFloat) -> CGImage? {
        let key = Key(contents: contents, origin: origin, scale: scale)

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = makeImage(with: contents, origin: origin, scale: scale) else {
            return nil
        }

        cache.setObject(image, forKey: key)

        return image
    }

    private func makeImage(with contents: DisplayListContents, origin: CGPoint, scale: CGFloat) -> CGImage? {
        guard let bounds = contents.bounds else {
            return nil
        }

        // Compute image size

        let width = Int((bounds.width + 1.5) * scale)
        let height = Int((bounds.height + 1.5) * scale)

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

        contents.render(in: bitmapContext, scale: scale)

        return bitmapContext.makeImage()
    }
}

#endif
