/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import DatadogInternal
import CommonCrypto

private let bitsPerComponent = 8
private var identifierKey: UInt8 = 0

extension UIImage: DatadogExtended {}

extension DatadogExtension where ExtendedType: UIImage {
    var identifier: String {
        if let hash = objc_getAssociatedObject(type, &identifierKey) as? String {
            return hash
        }

        let hash = md5Digest() ?? "\(type.hash)"
        objc_setAssociatedObject(type, &identifierKey, hash, .OBJC_ASSOCIATION_RETAIN)
        return hash
    }

    /// Generate a MD5 digest based on the image pixels.
    ///
    /// The digest value is computed in a greyscale image on a 100 pixels size maximum
    /// (width or height)
    ///
    /// - Returns: The MD5 digest
    private func md5Digest() -> String? {
        guard let cgImage = type.cgImage else {
            return nil
        }

        // rescale the image to maximum of 100 pixels width or height
        let size = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let ratio = max(1, size.width / 100, size.height / 100)

        let rect = CGRect(
            origin: .zero,
            size: CGSize(
                width: size.width / ratio,
                height: size.height / ratio
            )
        )

        // create a greyscale context
        let context = CGContext(
            data: nil,
            width: Int(rect.width),
            height: Int(rect.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let context = context else {
            return nil
        }

        // draw the image with low quality interpolation
        context.interpolationQuality = .low
        context.draw(cgImage, in: rect)

        guard let rawData = context.data else {
            return nil
        }

        // compute MD5 digest on the context data
        let length = context.bytesPerRow * context.height
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5(rawData, UInt32(length), &digest)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Compress the image to PNG.
    ///
    /// Scale down the image and apply tint color if necessary.
    ///
    /// - Parameters:
    ///   - maxSize: The maximum size of the image.
    ///   - tintColor: The tint color to apply.
    /// - Returns: The PNG data.
    func pngData(maxSize: CGSize = .init(width: 1_000, height: 1_000), tintColor: UIColor? = nil) -> Data? {
        if #available(iOS 13.0, *), type.isSymbolImage, let tintColor = tintColor {
            return png(image: type.withTintColor(tintColor), maxSize: maxSize, tintColor: nil)
        }

        return png(image: type, maxSize: maxSize, tintColor: tintColor)
    }

    /// Compress an image to PNG.
    /// 
    /// Scale down the image and apply tint color if necessary.
    ///
    /// - Parameters:
    ///   - image: The image to compress.
    ///   - maxSize: The maximum size of the image.
    ///   - tintColor: The tint color to apply.
    /// - Returns: The PNG data.
    private func png(image: UIImage, maxSize: CGSize, tintColor: UIColor?) -> Data? {
        let ratio = max(1, image.size.width / maxSize.width, image.size.height / maxSize.height)

        guard tintColor != nil || ratio > 1 else {
            return image.pngData()
        }

        let rect = CGRect(
            origin: .zero,
            size: CGSize(
                width: image.size.width / ratio,
                height: image.size.height / ratio
            )
        )

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.pngData { context in
            if let tintColor = tintColor {
                tintColor.setFill()
                context.fill(rect)
            }

            image.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
    }
}

#endif
