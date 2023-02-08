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

    func contentBase64String(of image: UIImage?) -> String? {
        guard let image = image, let imageData = image.pngData() else {
            return ""
        }

        var identifier: String
        if let md5 = image.md5 {
            identifier = md5
        } else {
            let md5 = imageData.md5
            image.md5 = md5
            identifier = md5
        }

        let dataLoadingStaus = cache[identifier]
        switch dataLoadingStaus {
        case .none:
            if let imageData = image.pngData(), image.size <= maxDimensions && imageData.count <= maxBytesSize {
                cache[identifier] = .loaded(imageData.base64EncodedString())
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

fileprivate extension CGSize {
    static func <= (lhs: CGSize, rhs: CGSize) -> Bool {
        return lhs.width <= rhs.width && lhs.height <= rhs.height
    }
}

fileprivate var imageMd5Key: UInt8 = 1

fileprivate extension UIImage {
    var md5: String? {
        set { objc_setAssociatedObject(self, &imageMd5Key, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN) }
        get { objc_getAssociatedObject(self, &imageMd5Key) as? String }
    }
}

import var CommonCrypto.CC_MD5_DIGEST_LENGTH
import func CommonCrypto.CC_MD5
import typealias CommonCrypto.CC_LONG

fileprivate extension Data {
    var md5: String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        var digestData = Data(count: length)

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
            withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress, let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(count)
                    CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }
        return digestData.map { String(format: "%02hhx", $0) }.joined()
    }
}
