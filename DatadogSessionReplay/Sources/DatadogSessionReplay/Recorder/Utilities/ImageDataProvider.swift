/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

internal class ImageDataProvider {
    enum DataLoadingStatus: Encodable {
        case loading, loaded(_ base64: String), ignored
    }

    private var cache: Cache<String, DataLoadingStatus>
    private var queue: Queue
    private let maxBytesSize: Int
    private let maxDimensions: CGSize

    internal init(
        cache: Cache<String, DataLoadingStatus> = .init(),
        queue: Queue = BackgroundAsyncQueue(named: "com.datadoghq.session-replay.image-data-provider"),
        maxBytesSize: Int = 64_000,
        maxDimensions: CGSize = CGSize(width: 120, height: 120)
    ) {
        self.cache = cache
        self.queue = queue
        self.maxBytesSize = maxBytesSize
        self.maxDimensions = maxDimensions
    }

    func contentBase64String(of imageView: UIImageView) -> String? {
        guard var image = imageView.image else {
            return ""
        }

        var identifier: String
        if let name = image.name {
            identifier = name
        } else {
            identifier = "\(image.hash)"
        }

        let tintColor = imageView.tintColor
        if let tintColor = tintColor {
            identifier += "\(hexStringFromColor(color: tintColor))"
        }

        let dataLoadingStaus = cache[identifier]
        switch dataLoadingStaus {
        case .loaded(let base64String):
            return base64String
        case .none:
            cache[identifier] = .loading

            queue.run { [unowned self] in
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
                    if let imageData = image.pngData(), image.size <= maxDimensions && imageData.count <= maxBytesSize {
                        cache[identifier] = .loaded(imageData.base64EncodedString())
                    } else {
                        cache[identifier] = .ignored
                    }
                }
            }
            return nil
        case .ignored:
            return ""
        case .loading:
            return nil
        }
    }

    private func hexStringFromColor(color: UIColor) -> String {
        let components = color.cgColor.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        let hexString = String.init(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
        print(hexString)
        return hexString
     }
}

extension CGSize: Comparable {
    public static func < (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width < rhs.width && lhs.height < rhs.height
    }
}
