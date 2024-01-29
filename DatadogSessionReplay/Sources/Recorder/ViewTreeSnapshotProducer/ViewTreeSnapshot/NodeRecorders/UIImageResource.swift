/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIImageResource {
    internal let image: UIImage
    internal let tintColor: UIColor?

    internal init(image: UIImage, tintColor: UIColor?) {
        self.image = image
        self.tintColor = tintColor
    }
}

extension UIImageResource: Resource {
    func calculateIdentifier() -> String {
        var identifier = image.srIdentifier
        if let tintColorIdentifier = tintColor?.srIdentifier {
            identifier += tintColorIdentifier
        }
        return identifier
    }

    func calculateData() -> Data {
        if let tintColor = tintColor {
            if #available(iOS 13.0, *) {
                if image.isSymbolImage {
                    return image.withTintColor(tintColor)
                        .scaledDownToApproximateSize(SessionReplay.maxObjectSize)
                } else {
                    return manuallyTintedImageData()
                }
            } else {
                return manuallyTintedImageData()
            }
        } else {
            return image.scaledDownToApproximateSize(SessionReplay.maxObjectSize)
        }
    }

    /// Provides mitigation for template images that fail to tint programatically outside of `UIImageView` or other system container.
    private func manuallyTintedImageData() -> Data {
        return image
            .tint(color: tintColor)
            .scaledDownToApproximateSize(SessionReplay.maxObjectSize)
    }
}

fileprivate extension UIImage {
    func tint(color: UIColor?, blendMode: CGBlendMode = .destinationIn) -> UIImage {
        guard let color = color else {
            return self
        }
        let drawRect = CGRect(x: 0,y: 0,width: size.width,height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        color.setFill()
        UIRectFill(drawRect)
        draw(in: drawRect, blendMode: blendMode, alpha: 1.0)
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return tintedImage ?? self
    }
}
#endif
