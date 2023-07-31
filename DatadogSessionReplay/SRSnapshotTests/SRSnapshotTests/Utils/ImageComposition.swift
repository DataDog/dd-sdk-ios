/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// Constants for composing side-by-side image from two images.
private struct Constants {
    /// Margins to apply around both images.
    /// Hint: the `top` is bigger, so we can render `appImageLabel` and `wireframesImageLabel` above each image.
    static let edgeInsets = UIEdgeInsets(top: -30, left: -5, bottom: -5, right: -5)
    /// The label rendered above app's image.
    static let appImageLabel = "Actual UI:"
    /// The label rendered above wireframes image.
    static let wireframesImageLabel = "Wireframes:"
}

/// Puts two images side-by-side, adds titles and returns new, composite image.
internal func createSideBySideImage(
    leftImage image1: UIImage,
    rightImage image2: UIImage,
    leftTitle: String = Constants.appImageLabel,
    rightTitle: String = Constants.wireframesImageLabel
) -> UIImage {
    var leftRect = CGRect(origin: .zero, size: image1.size)
    var rightRect = CGRect(origin: .init(x: image1.size.width, y: 0), size: image2.size)
    let imageRect = leftRect.union(rightRect)
        .inset(by: Constants.edgeInsets)

    let dx = -Constants.edgeInsets.left
    let dy = -Constants.edgeInsets.top
    leftRect = leftRect.offsetBy(dx: dx, dy: dy)
    rightRect = rightRect.offsetBy(dx: dx, dy: dy)

    let format = UIGraphicsImageRendererFormat()
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: imageRect.size, format: format)

    return renderer.image { context in
        // Fill the image:
        context.cgContext.setFillColor(UIColor.white.cgColor)
        context.cgContext.addRect(CGRect(origin: .zero, size: imageRect.size))
        context.cgContext.fillPath()

        // Draw both images:
        image1.draw(at: leftRect.origin)
        image2.draw(at: rightRect.origin)

        // Draw strokes around both images
        context.cgContext.setLineWidth(2)
        context.cgContext.setStrokeColor(UIColor.black.cgColor)
        context.cgContext.addRect(leftRect)
        context.cgContext.addRect(rightRect)
        context.cgContext.strokePath()

        // Add image titles
        let textAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 15),
            NSAttributedString.Key.foregroundColor: #colorLiteral(red: 0.3882352941, green: 0.1725490196, blue: 0.6509803922, alpha: 1),
        ]

        let leftTextRect = leftRect.offsetBy(dx: 2, dy: -25)
        let rightTextRect = rightRect.offsetBy(dx: 2, dy: -25)

        leftTitle.draw(in: leftTextRect, withAttributes: textAttributes)
        rightTitle.draw(in: rightTextRect, withAttributes: textAttributes)
    }
}

/// It extracts left and right images from the composite image produced by `createSideBySideImage(left:right:) -> UIImage`.
internal func extractSideBySideImages(image: UIImage) -> (leftImage: UIImage, rightImage: UIImage) {
    let negativeInsets = UIEdgeInsets(
        top: -Constants.edgeInsets.top,
        left: -Constants.edgeInsets.left,
        bottom: -Constants.edgeInsets.bottom,
        right: -Constants.edgeInsets.right
    )
    let imageRect = CGRect(origin: .zero, size: image.size)
        .inset(by: negativeInsets)
    let singleImageSize = CGSize(width: imageRect.width * 0.5, height: imageRect.height)
    let leftRect = CGRect(origin: imageRect.origin, size: singleImageSize)
    let rightRect = CGRect(origin: .init(x: imageRect.origin.x + singleImageSize.width, y: imageRect.origin.y), size: singleImageSize)

    let format = UIGraphicsImageRendererFormat()
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: singleImageSize, format: format)

    let leftImage = renderer.image { context in
        image.draw(at: leftRect.origin.applying(.init(scaleX: -1, y: -1)))
    }
    let rightImage = renderer.image { context in
        image.draw(at: rightRect.origin.applying(.init(scaleX: -1, y: -1)))
    }

    return (leftImage: leftImage, rightImage: rightImage)
}

/// Renders two images on top of each other with using `.difference` blend mode to surface differences.
internal func overlayImages(image1: UIImage, image2: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: image1.size, format: format)

    let overlay = renderer.image { context in
        image1.draw(at: .zero)
        image2.draw(at: .zero, blendMode: .difference, alpha: 1)
    }
    return overlay
}
