/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIImageView {
    private var scaleAspectFillRect: CGRect {
        guard let image = image else {
            return bounds
        }

        let scale: CGFloat
        if (image.size.width - frame.size.width) < (image.size.height - frame.size.height) {
            scale = bounds.width / image.size.width
        } else {
            scale = bounds.height / image.size.height
        }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private var scaleAspectFitRect: CGRect {
        guard let image = image else {
            return bounds
        }

        let imageAspectRatio = image.size.height / image.size.width
        let frameAspectRatio = frame.height / frame.width

        var x, y, width, height: CGFloat
        if imageAspectRatio > frameAspectRatio {
            height = frame.height
            width = height / imageAspectRatio
            x = (frame.width / 2) - (width / 2)
            y = 0
        } else {
            width = frame.width
            height = width * imageAspectRatio
            x = 0
            y = (frame.height / 2) - (height / 2)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func imageFrame(in frame: CGRect) -> CGRect {
        let imageSize = image?.size ?? .zero
        let imageFrame: CGRect
        switch contentMode {
        case .scaleAspectFit:
            let realImageRect = scaleAspectFitRect
            imageFrame = CGRect(
                x: frame.origin.x + realImageRect.origin.x,
                y: frame.origin.y + realImageRect.origin.y,
                width: realImageRect.size.width,
                height: realImageRect.size.height
            )

        case .scaleAspectFill:
            let realImageRect = scaleAspectFillRect
            imageFrame = CGRect(
                x: frame.origin.x + realImageRect.origin.x,
                y: frame.origin.y + realImageRect.origin.y,
                width: realImageRect.size.width,
                height: realImageRect.size.height
            )
        case .redraw, .center:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width) / 2,
                y: frame.origin.y + (frame.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        case .scaleToFill:
            return frame

        case .topLeft:
            imageFrame = CGRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: imageSize.width,
                height: imageSize.height
            )
        case .topRight:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width),
                y: frame.origin.y,
                width: imageSize.width,
                height: imageSize.height
            )
        case .bottomLeft:
            imageFrame = CGRect(
                x: frame.origin.x,
                y: frame.origin.y + (frame.height - imageSize.height),
                width: imageSize.width,
                height: imageSize.height
            )
        case .bottomRight:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width),
                y: frame.origin.y + (frame.height - imageSize.height),
                width: imageSize.width,
                height: imageSize.height
            )
        case .top:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width) / 2,
                y: frame.origin.y,
                width: imageSize.width,
                height: imageSize.height
            )
        case .bottom:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width) / 2,
                y: frame.origin.y + (frame.height - imageSize.height),
                width: imageSize.width,
                height: imageSize.height
            )
        case .left:
            imageFrame = CGRect(
                x: frame.origin.x,
                y: frame.origin.y + (frame.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        case .right:
            imageFrame = CGRect(
                x: frame.origin.x + (frame.width - imageSize.width),
                y: frame.origin.y + (frame.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )

        @unknown default:
            imageFrame = frame
        }

        if clipsToBounds {
            return CGRect(
                x: (imageFrame.width > frame.width) ? frame.origin.x : imageFrame.origin.x,
                y: (imageFrame.height > frame.height) ? frame.origin.y : imageFrame.origin.y,
                width: (imageFrame.width > frame.width) ? frame.width : imageFrame.width,
                height: (imageFrame.height > frame.height) ? frame.height : imageFrame.height
            )
        } else {
            return imageFrame
        }
    }
}
