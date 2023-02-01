/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UIImageViewRecorder: NodeRecorder {
    let imageDataProvider = ImageDataProvider()
    func semantics(
        of view: UIView,
        with attributes: ViewAttributes,
        in context: ViewTreeSnapshotBuilder.Context
    ) -> NodeSemantics? {
        guard let imageView = view as? UIImageView else {
            return nil
        }
        guard attributes.hasAnyAppearance || imageView.image != nil else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeID2(for: imageView)
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
            wireframeID: ids.0,
            imageWireframeID: ids.1,
            attributes: attributes,
            contentFrame: contentFrame,
            clipsToBounds: imageView.clipsToBounds,
            base64: imageDataProvider.lazyBase64String(of: imageView)
        )
        return SpecificElement(wireframesBuilder: builder, recordSubtree: true)
    }
}

internal struct UIImageViewWireframesBuilder: NodeWireframesBuilder {
    struct Defaults {
        /// Until we suppport images in SR V.x., this color is used as placeholder in SR V.0.:
        static let placeholderColor: CGColor = UIColor.systemGray.cgColor
    }

    let wireframeID: WireframeID

    var wireframeRect: CGRect {
        attributes.frame
    }

    let imageWireframeID: WireframeID

    let attributes: ViewAttributes

    let contentFrame: CGRect?

    let clipsToBounds: Bool

    let base64: String?

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
                    base64: base64,
                    id: imageWireframeID,
                    frame: contentFrame,
                    clip: clipsToBounds ? clip : nil
                )
            )
        }
        return wireframes
    }
}
