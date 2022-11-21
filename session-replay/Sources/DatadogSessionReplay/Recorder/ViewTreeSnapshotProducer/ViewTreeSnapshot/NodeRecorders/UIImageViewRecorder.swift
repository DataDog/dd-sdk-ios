/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

        // TODO: RUMM-2455
        // Enhance image placeholders rendering by considering `.contentMode` and resizing
        // the wireframe to fit the actual image, not surrounding `UIImageView`.
        let imageFrame = attributes.frame

        let builder = UIImageViewWireframesBuilder(
            wireframeID: context.ids.nodeID(for: imageView),
            attributes: attributes,
            imageFrame: imageFrame
        )
        return SpecificElement(wireframesBuilder: builder)
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
    /// The actual frame of the image, in screen coordinates.
    let imageFrame: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: imageFrame,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor ?? Defaults.placeholderColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
