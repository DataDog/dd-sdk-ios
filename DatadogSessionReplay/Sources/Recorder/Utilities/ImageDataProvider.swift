/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

internal class ImageDataProvider {

    private var cache: Cache<String, String>

    private let maxBytesSize: Int
    private let maxDimensions: CGSize

    internal init(
        cache: Cache<String, String> = .init(),
        maxBytesSize: Int = 10_000,
        maxDimensions: CGSize = CGSize(width: 40, height: 40)
    ) {
        self.cache = cache
        self.maxBytesSize = maxBytesSize
        self.maxDimensions = maxDimensions
    }

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor? = nil
    ) -> String {
        autoreleasepool {
            guard var image = image else {
                return ""
            }
            if #available(iOS 13.0, *), let tintColor = tintColor {
                image = image.withTintColor(tintColor)
            }

            var identifier = image.srIdentifier
            if let tintColorIdentifier = tintColor?.srIdentifier {
                identifier += tintColorIdentifier
            }
            if let base64EncodedImage = cache[identifier] {
                return base64EncodedImage
            } else {
                let base64EncodedImage = image.compressToTargetSize(maxBytesSize).base64EncodedString()
                cache[identifier, base64EncodedImage.count] = base64EncodedImage
                return base64EncodedImage
            }
        }
    }
}

fileprivate extension CGSize {
    static func <= (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width <= rhs.width && lhs.height <= rhs.height
    }
}

extension UIImage {
    var srIdentifier: String {
        return "\(hash)"
    }
}

fileprivate extension UIImage {
    func compressToTargetSize(_ targetSize: Int) -> Data {
        var compressionQuality: CGFloat = 1.0
        guard var imageData = pngData() else {
            return Data()
        }
        guard imageData.count >= targetSize else {
            return imageData
        }
        var image = self
        while imageData.count > targetSize {
            compressionQuality -= 0.1
            imageData = image.jpegData(compressionQuality: compressionQuality) ?? Data()

            if imageData.count > targetSize {
                image = image.scaledImage(by: 0.9)
            }
        }
        return imageData
    }

    func scaledImage(by percentage: CGFloat) -> UIImage {
        let newSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension UIColor {
    var srIdentifier: String {
        return "\(hash)"
    }
}
