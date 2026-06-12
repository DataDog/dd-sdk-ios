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
    case placeholder
}

/// Redacts images before they are converted into replay payloads.
@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageRedactor {
    private final class CacheKey: NSObject {
        private let identifier: ObjectIdentifier
        private let action: ImageRedactionAction

        init(image: UIImage, action: ImageRedactionAction) {
            self.identifier = ObjectIdentifier(image)
            self.action = action
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(identifier)
            hasher.combine(action)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else {
                return false
            }

            return identifier == other.identifier && action == other.action
        }
    }

    private enum Constants {
        static let fallbackRedactionColor = UIColor.black
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
            return .placeholder
        case .redactText, .redactFaces:
            return .image(try redactedImage(for: image, action: action))
        }
    }

    private func redactedImage(
        for image: UIImage,
        action: ImageRedactionAction
    ) throws -> UIImage {
        let cacheKey = CacheKey(image: image, action: action)

        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let rectangles: [CGRect]
        switch action {
        case .redactText:
            rectangles = try image.textRectangles()
        case .redactFaces:
            rectangles = try image.faceRectangles()
        case .none, .placeholder:
            rectangles = []
        }

        let redactionColor = image.dominantColor() ?? Constants.fallbackRedactionColor
        let redactedImage = image.image(redactingRectangles: rectangles, color: redactionColor)
        cache.setObject(redactedImage, forKey: cacheKey)

        return redactedImage
    }
}
#endif
