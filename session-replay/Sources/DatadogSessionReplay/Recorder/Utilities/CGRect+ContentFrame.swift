/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension CGRect {
    func contentFrame(
        for contentSize: CGSize,
        using contentMode: UIView.ContentMode
    ) -> CGRect {
        guard width > 0 && height > 0 && contentSize.width > 0 && contentSize.height > 0 else {
            return .zero
        }
        let contentFrame: CGRect
        switch contentMode {
        case .scaleAspectFit:
            let actualContentRect = self.size.scaleAspectFitRect(for: contentSize)
            contentFrame = CGRect(
                x: self.origin.x + actualContentRect.origin.x,
                y: self.origin.y + actualContentRect.origin.y,
                width: actualContentRect.size.width,
                height: actualContentRect.size.height
            )

        case .scaleAspectFill:
            let actualContentRect = self.size.scaleAspectFillRect(for: contentSize)
            contentFrame = CGRect(
                x: self.origin.x + actualContentRect.origin.x,
                y: self.origin.y + actualContentRect.origin.y,
                width: actualContentRect.size.width,
                height: actualContentRect.size.height
            )
        case .redraw, .center:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .scaleToFill:
            contentFrame = self

        case .topLeft:
            contentFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .topRight:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomLeft:
            contentFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomRight:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .top:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottom:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width) / 2,
                y: self.origin.y + (self.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .left:
            contentFrame = CGRect(
                x: self.origin.x,
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .right:
            contentFrame = CGRect(
                x: self.origin.x + (self.width - contentSize.width),
                y: self.origin.y + (self.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )

        @unknown default:
            contentFrame = self
        }
        return contentFrame
    }
}

extension CGSize {
    var aspectRatio: CGFloat {
        guard width > 0 else {
            return 0
        }
        return height / width
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

        var x, y, width, height: CGFloat
        if imageAspectRatio > aspectRatio {
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
