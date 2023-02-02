/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

class ImageDataProvider {
    enum DataLoadingStatus: Encodable {
        case loading, loaded(_ base64: String), ignored
    }

    private var cache = Cache<String, DataLoadingStatus>()

    private let maxBytesSize = 64_000
    private let maxSize = CGSize(width: 120, height: 120)

    private var emptyImageData = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="

    func contentBase64String(of imageView: UIImageView) -> String? {
        guard var image = imageView.image else {
            return emptyImageData
        }

        var identifier: String
        if let name = image.name {
            identifier = name
        } else {
            identifier = "\(image.hash)"
        }

        let tintColor = imageView.tintColor
        if let tintColorHash = tintColor?.hash {
            identifier += "-\(tintColorHash)"
        }

        let dataLoadingStaus = cache[identifier]
        switch dataLoadingStaus {
        case .loaded(let base64String):
            return base64String
        case .none:
            cache[identifier] = .loading

            DispatchQueue.global(qos: .background).async { [unowned self] in
                if image.name != nil {
                    if let compressed = image.compressToTargetSize(maxBytesSize) {
                        cache[identifier] = .loaded(compressed.base64EncodedString())
                    } else {
                        cache[identifier] = .ignored
                    }
                } else {
                    if let tintColor = tintColor, #available(iOS 13.0, *) {
                        image = image.withTintColor(tintColor)
                    }
                    if let imageData = image.pngData(), image.size <= maxSize && imageData.count <= maxBytesSize {
                        cache[identifier] = .loaded(imageData.base64EncodedString())
                    }
                    else {
                        cache[identifier] = .ignored
                    }
                }
            }
            return nil
        case .ignored:
            return emptyImageData
        case .loading:
            return nil
        }
    }
}

extension CGSize: Comparable {
    public static func < (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width < rhs.width && lhs.height < rhs.height
    }
}
