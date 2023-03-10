/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

internal protocol ImageDataProviding {
    func contentBase64String(
        of image: UIImage?
    ) -> String

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor?
    ) -> String
}

internal class ImageDataProvider: ImageDataProviding {
    private var cache: Cache<String, String>

    private let maxBytesSize: Int

    internal init(
        cache: Cache<String, String> = .init(),
        maxBytesSize: Int = 10_000
    ) {
        self.cache = cache
        self.maxBytesSize = maxBytesSize
    }

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor?
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
                let base64EncodedImage = image.pngData()?.base64EncodedString() ?? ""
                cache[identifier, base64EncodedImage.count] = base64EncodedImage
                return base64EncodedImage
            }
        }
    }

    func contentBase64String(of image: UIImage?) -> String {
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
        return "\(hash)"
    }
}

extension UIColor {
    var srIdentifier: String {
        return "\(hash)"
    }
}
