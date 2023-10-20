/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

internal struct ImageResource {
    let identifier: String
    let base64: String
}

internal protocol ImageDataProviding {
    func contentBase64String(
        of image: UIImage?
    ) -> ImageResource?

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor?
    ) -> ImageResource?
}

internal final class ImageDataProvider: ImageDataProviding {
    private var cache: Cache<String, String>

    private let desiredMaxBytesSize: Int

    internal init(
        cache: Cache<String, String> = .init(),
        desiredMaxBytesSize: Int = 15.KB
    ) {
        self.cache = cache
        self.desiredMaxBytesSize = desiredMaxBytesSize
    }

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor?
    ) -> ImageResource? {
        autoreleasepool { () -> ImageResource? in
            guard var image = image else {
                return nil
            }
            var identifier = image.srIdentifier
            if let tintColorIdentifier = tintColor?.srIdentifier {
                identifier += tintColorIdentifier
            }
            if let base64EncodedImage = cache[identifier] {
                return ImageResource(identifier: identifier, base64: base64EncodedImage)
            } else {
                if #available(iOS 13.0, *), let tintColor = tintColor {
                    image = image.withTintColor(tintColor)
                }
                let base64EncodedImage = image.scaledDownToApproximateSize(desiredMaxBytesSize).base64EncodedString()
                cache[identifier, base64EncodedImage.count] = base64EncodedImage
                return ImageResource(identifier: identifier, base64: base64EncodedImage)
            }
        }
    }

    func contentBase64String(of image: UIImage?) -> ImageResource? {
        contentBase64String(of: image, tintColor: nil)
    }
}

fileprivate extension CGSize {
    static func <= (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width <= rhs.width && lhs.height <= rhs.height
    }
}

extension UIImage {
    var srIdentifier: String {
        return md5Hash
    }
}

extension UIColor {
    var srIdentifier: String {
        return "\(hash)"
    }
}

import CryptoKit

private var md5HashKey: UInt8 = 11
fileprivate extension UIImage {
    private struct AssociatedKeys {

    }

    var md5Hash: String {
        if let hash = objc_getAssociatedObject(self, &md5HashKey) as? String {
            return hash
        }

        let hash = computeMD5Hash()
        objc_setAssociatedObject(self, &md5HashKey, hash, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return hash
    }

    private func computeMD5Hash() -> String {
        guard let imageData = self.pngData() else {
            return ""
        }
        if #available(iOS 13.0, *) {
            return Insecure.MD5.hash(data: imageData).map { String(format: "%02hhx", $0) }.joined()
        } else {
            return "\(hash)"
        }
    }
}
#endif
