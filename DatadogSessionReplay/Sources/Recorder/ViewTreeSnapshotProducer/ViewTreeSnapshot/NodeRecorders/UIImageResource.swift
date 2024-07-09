/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIImageResource {
    public let image: UIImage
    private let tintColor: UIColor?

    internal init(image: UIImage, tintColor: UIColor?) {
        self.image = image
        self.tintColor = tintColor
    }
}

extension UIImageResource: Resource {
    func calculateIdentifier() -> String {
        var identifier = image.dd.srIdentifier
        if let tintColorIdentifier = tintColor?.srIdentifier {
            identifier += tintColorIdentifier
        }
        return identifier
    }

    func calculateData() -> Data {
        guard let tintColor = tintColor else {
            return image.scaledDownToApproximateSize(SessionReplay.maxObjectSize)
        }
        if #available(iOS 13.0, *), image.isSymbolImage {
            return image.withTintColor(tintColor)
                .scaledDownToApproximateSize(SessionReplay.maxObjectSize)
        } else {
            return manuallyTintedImageData()
        }
    }

    /// Provides mitigation for template images that fail to tint programatically outside of `UIImageView` or other system container.
    private func manuallyTintedImageData() -> Data {
        return image
            .scaledDownToApproximateSize(SessionReplay.maxObjectSize, tint: tintColor)
    }
}
#endif
