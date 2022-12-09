/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UIImageViewRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard let imageView = view as? UIImageView else {
            return nil
        }

        let hasImage = imageView.image != nil

        guard hasImage || attributes.hasAnyAppearance else {
            return InvisibleElement.constant
        }

        let builder = UIImageViewWireframesBuilder(
            wireframeID: context.ids.nodeID(for: imageView),
            attributes: attributes,
            imageFrame: imageView.imageFrame(in: attributes.frame)
        )
        return SpecificElement(wireframesBuilder: builder, recordSubtree: false)
    }
}

internal struct UIImageViewWireframesBuilder: NodeWireframesBuilder {
    struct Defaults {
        /// Until we suppport images in SR V.x., this color is used as placeholder in SR V.0.:
        static let placeholderColor: CGColor = UIColor.systemGray.cgColor
    }

    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes

    let wireframeRect: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: wireframeRect,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor ?? Defaults.placeholderColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}

extension UIImageView {
    var scaleAspectFillRect: CGRect {
        guard let image = image else { return bounds }

        let scale: CGFloat
        if image.size.width < image.size.height {
            scale = bounds.width / image.size.width
        } else {
            scale = bounds.height / image.size.height
        }

        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let x = (bounds.width - size.width) / 2.0
        let y = (bounds.height - size.height) / 2.0

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    var scaleAspectFitRect: CGRect {
        guard let image = image else {
            return .zero
        }
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        let wv = frame.width
        let hv = frame.height

        let ri = imageHeight / imageWidth
        let rv = hv / wv

        var x, y, w, h: CGFloat

        if ri > rv {
            h = hv
            w = h / ri
            x = (wv / 2) - (w / 2)
            y = 0
        } else {
            w = wv
            h = w * ri
            x = 0
            y = (hv / 2) - (h / 2)
        }
        return CGRect(x: x, y: y, width: w, height: h)
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
                height: (imageFrame.height > frame.height) ?  frame.height : imageFrame.height
            )
        } else {
            return imageFrame
        }
    }
}
