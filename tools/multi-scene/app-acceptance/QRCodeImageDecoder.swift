// Copyright © Datadog, Inc. All rights reserved.

import CoreImage
import Foundation
import ImageIO

enum QRCodeImageDecoder {
    enum Failure: Error {
        case unreadableImage
        case missingOrAmbiguousCode
    }

    static func message(in data: Data) throws -> String {
        try Task.checkCancellation()
        guard data.count <= 25 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 4096,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw Failure.unreadableImage
        }
        try Task.checkCancellation()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let codes = detector?.features(in: CIImage(cgImage: thumbnail)).compactMap { $0 as? CIQRCodeFeature } ?? []
        guard codes.count == 1, let message = codes.first?.messageString, !message.isEmpty else {
            throw Failure.missingOrAmbiguousCode
        }
        try Task.checkCancellation()
        return message
    }
}
