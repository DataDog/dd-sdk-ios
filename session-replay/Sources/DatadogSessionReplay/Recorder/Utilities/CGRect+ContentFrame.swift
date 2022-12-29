/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension CGRect {
    func contentFrame(
        for contentSize: CGSize?,
        using contentMode: UIView.ContentMode
    ) -> CGRect? {
        guard let contentSize = contentSize else {
            return nil
        }
        let imageFrame: CGRect
        switch contentMode {
        case .scaleAspectFit:
            let realImageRect = self.size.scaleAspectFitRect(for: contentSize)
            imageFrame = CGRect(
                x: self.origin.x + realImageRect.origin.x,
                y: self.origin.y + realImageRect.origin.y,
                width: realImageRect.size.width,
                height: realImageRect.size.height
            )

        case .scaleAspectFill:
            let realImageRect = self.size.scaleAspectFillRect(for: contentSize)
            imageFrame = CGRect(
                x: self.origin.x + realImageRect.origin.x,
                y: self.origin.y + realImageRect.origin.y,
                width: realImageRect.size.width,
                height: realImageRect.size.height
            )
        case .redraw, .center:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .scaleToFill:
            imageFrame = self

        case .topLeft:
            imageFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .topRight:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomLeft:
            imageFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomRight:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .top:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottom:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .left:
            imageFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .right:
            imageFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )

        @unknown default:
            imageFrame = self
        }
        return imageFrame
    }
}

fileprivate extension CGSize {
    func scaleAspectFillRect(for contentSize: CGSize) -> CGRect {
        let scale: CGFloat
        if (contentSize.width - width) < (contentSize.height - height) {
            scale = width / contentSize.width
        } else {
            scale = height / contentSize.height
        }
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)

        return CGRect(
            x: (width - size.width) / 2,
            y: (height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func scaleAspectFitRect(for contentSize: CGSize) -> CGRect {
        let imageAspectRatio = contentSize.height / contentSize.width
        let frameAspectRatio = self.height / self.width

        var x, y, width, height: CGFloat
        if imageAspectRatio > frameAspectRatio {
            height = self.height
            width = height / imageAspectRatio
            x = (self.width / 2) - (width / 2)
            y = 0
        } else {
            width = self.width
            height = width * imageAspectRatio
            x = 0
            y = (self.height / 2) - (height / 2)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
