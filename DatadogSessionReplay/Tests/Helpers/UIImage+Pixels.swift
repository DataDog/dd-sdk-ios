/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension UIImage {
    convenience init?(
        pixels: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat = 1,
        bitsPerPixel: Int = 32,
        bytesPerRow: Int? = nil,
        colorSpace: CGColorSpace? = nil,
        bitmapInfo: CGBitmapInfo = .byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
    ) {
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow ?? width * (bitsPerPixel / UInt8.bitWidth),
                space: space,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return nil
        }
        self.init(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
#endif
