/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// Redacted image or placeholder instruction.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageRedactionResult {
    case image(UIImage)
    case placeholder(UIColor)
}

/// Redacts images before they are converted into replay payloads.
@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageRedactor {
    private final class CacheKey: NSObject {
        private let identifier: ObjectIdentifier

        init(image: UIImage) {
            self.identifier = ObjectIdentifier(image)
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(identifier)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else {
                return false
            }

            return identifier == other.identifier
        }
    }

    private let cache = NSCache<CacheKey, UIImage>()

    func redact(
        _ image: UIImage,
        action: ImageRedactionAction
    ) throws -> ImageRedactionResult {
        switch action {
        case .none:
            return .image(image)
        case .placeholder:
            return .placeholder(image.redactionColor)
        case .redactText:
            return .image(try imageRedactingText(from: image))
        }
    }

    private func imageRedactingText(from image: UIImage) throws -> UIImage {
        let cacheKey = CacheKey(image: image)

        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let rectangles = try image.textRectangles()
        let redactedImage = image.image(redactingRectangles: rectangles)
        cache.setObject(redactedImage, forKey: cacheKey)

        return redactedImage
    }
}
#endif
