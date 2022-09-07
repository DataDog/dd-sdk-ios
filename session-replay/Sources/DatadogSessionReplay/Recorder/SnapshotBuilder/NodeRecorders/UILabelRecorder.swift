/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal struct UILabelRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard let label = view as? UILabel else {
            return nil
        }

        let hasVisibleText = !(label.text?.isEmpty ?? true)

        guard hasVisibleText || attributes.hasAnyAppearance else {
            return InvisibleElement.constant
        }

        let builder = UILabelWireframesBuilder(
            attributes: attributes,
            text: label.text ?? "",
            textColor: label.textColor?.cgColor,
            font: label.font
        )
        return SpecificElement(wireframesBuilder: builder)
    }
}

internal struct UILabelWireframesBuilder: NodeWireframesBuilder {
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside label.
    let text: String
    /// The color of the text.
    let textColor: CGColor?
    /// The font used by the label.
    let font: UIFont?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        // The actual frame of the text, which is smaller than the frame of the label:
        let textFrame = CGRect(
            x: attributes.frame.minX,
            y: attributes.frame.minY + (attributes.frame.height - attributes.intrinsicContentSize.height) * 0.5,
            width: attributes.intrinsicContentSize.width,
            height: attributes.intrinsicContentSize.height
        )

        return [
            builder.createTextWireframe(
                frame: attributes.frame,
                text: text,
                textFrame: textFrame,
                textColor: textColor,
                font: font,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
