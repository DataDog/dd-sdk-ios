/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class UIImageViewRecorder: NodeRecorder {
    /// An option for overriding default semantics from parent recorder.
    var semanticsOverride: (UIImageView, ViewAttributes) -> NodeSemantics? = { imageView, _ in
        let className = "\(type(of: imageView))"
        // This gets effective on iOS 15.0+ which is the earliest version that displays some elements in popover views.
        // Here we explicitly ignore the "shadow" effect applied to popover.
        let isSystemShadow = className == "_UICutoutShadowView"
        return isSystemShadow ? IgnoredElement(subtreeStrategy: .ignore) : nil
    }

    private let imageDataProvider = ImageDataProvider()

    func semantics(
        of view: UIView,
        with attributes: ViewAttributes,
        in context: ViewTreeRecordingContext
    ) -> NodeSemantics? {
        guard let imageView = view as? UIImageView else {
            return nil
        }
        if let semantics = semanticsOverride(imageView, attributes) {
            return semantics
        }
        guard attributes.hasAnyAppearance || imageView.image != nil else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(2, for: imageView)
        let contentFrame: CGRect?
        if let image = imageView.image {
            contentFrame = attributes.frame.contentFrame(
                for: image.size,
                using: imageView.contentMode
            )
        } else {
            contentFrame = nil
        }
        let builder = UIImageViewWireframesBuilder(
            wireframeID: ids[0],
            imageWireframeID: ids[1],
            attributes: attributes,
            contentFrame: contentFrame,
            clipsToBounds: imageView.clipsToBounds,
            image: imageView.image,
            imageTintColor: imageView.tintColor,
            imageDataProvider: imageDataProvider
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }
}

internal struct UIImageViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID

    var wireframeRect: CGRect {
        attributes.frame
    }

    let imageWireframeID: WireframeID

    let attributes: ViewAttributes

    let contentFrame: CGRect?

    let clipsToBounds: Bool

    let image: UIImage?

    let imageTintColor: UIColor?

    let imageDataProvider: ImageDataProvider

    private var clip: SRContentClip? {
        guard let contentFrame = contentFrame else {
            return nil
        }
        let top = max(relativeIntersectedRect.origin.y - contentFrame.origin.y, 0)
        let left = max(relativeIntersectedRect.origin.x - contentFrame.origin.x, 0)
        let bottom = max(contentFrame.height - (relativeIntersectedRect.height + top), 0)
        let right = max(contentFrame.width - (relativeIntersectedRect.width + left), 0)
        return SRContentClip(
            bottom: Int64(withNoOverflow: bottom),
            left: Int64(withNoOverflow: left),
            right: Int64(withNoOverflow: right),
            top: Int64(withNoOverflow: top)
        )
    }

    private var relativeIntersectedRect: CGRect {
        guard let contentFrame = contentFrame else {
            return .zero
        }
        return attributes.frame.intersection(contentFrame)
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        var wireframes = [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: attributes.frame,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
        if let contentFrame = contentFrame {
            wireframes.append(
                builder.createImageWireframe(
                    base64: imageDataProvider.contentBase64String(
                        of: image,
                        tintColor: imageTintColor
                    ),
                    id: imageWireframeID,
                    frame: contentFrame,
                    clip: clipsToBounds ? clip : nil
                )
            )
        }
        return wireframes
    }
}
