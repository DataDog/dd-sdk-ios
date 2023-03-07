/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

internal class ImageDataProvider {
    enum DataLoadingStatus: Encodable {
        case loaded(_ base64: String), ignored
    }

    private var cache: Cache<String, DataLoadingStatus>

    private let maxBytesSize: Int
    private let maxDimensions: CGSize

    internal init(
        cache: Cache<String, DataLoadingStatus> = .init(),
        maxBytesSize: Int = 64_000,
        maxDimensions: CGSize = CGSize(width: 120, height: 120)
    ) {
        self.cache = cache
        self.maxBytesSize = maxBytesSize
        self.maxDimensions = maxDimensions
    }

    func contentBase64String(
        of image: UIImage?,
        tintColor: UIColor? = nil
    ) -> String? {
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
            let dataLoadingStaus = cache[identifier]
            switch dataLoadingStaus {
            case .none:
                if let imageData = image.pngData(), image.size <= maxDimensions && imageData.count <= maxBytesSize {
                    let base64EncodedImage = imageData.base64EncodedString()
                    cache[identifier, base64EncodedImage.count] = .loaded(base64EncodedImage)
                } else {
                    cache[identifier] = .ignored
                }
                return contentBase64String(of: image)
            case .loaded(let base64String):
                return base64String
            case .ignored:
                return ""
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

extension UIColor {
    var srIdentifier: String {
        return "\(hash)"
    }
}
