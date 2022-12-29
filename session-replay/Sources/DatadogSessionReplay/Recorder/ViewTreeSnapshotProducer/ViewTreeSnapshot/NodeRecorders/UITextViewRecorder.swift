/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UITextViewRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard let textView = view as? UITextView else {
            return nil
        }
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }
        let builder = UITextViewWireframesBuilder(
            wireframeID: context.ids.nodeID(for: textView),
            attributes: attributes,
            text: textView.text,
            textColor: textView.textColor?.cgColor ?? UIColor.black.cgColor,
            font: textView.font,
            textObfuscator: context.recorder.privacy == .maskAll ? context.textObfuscator : nopTextObfuscator,
            wireframeRect: CGRect(origin: textView.contentOffset, size: textView.contentSize)
        )
        return SpecificElement(wireframesBuilder: builder, recordSubtree: true)
    }
}

internal struct UITextViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside text field.
    let text: String
    /// The color of the text.
    let textColor: CGColor?
    /// The font used by the text field.
    let font: UIFont?
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating
    /// The frame of the text content
    var wireframeRect: CGRect

    private var clip: SRContentClip {
        let top = abs(wireframeRect.origin.y)
        let left = abs(wireframeRect.origin.x)
        let bottom = max(wireframeRect.height - attributes.frame.height - top, 0)
        let right = max(wireframeRect.width - attributes.frame.width - left, 0)
        return SRContentClip(
            bottom: Int64(withNoOverflow: bottom),
            left: Int64(withNoOverflow: left),
            right: Int64(withNoOverflow: right),
            top: Int64(withNoOverflow: top)
        )
    }

    private var relativeIntersectedRect: CGRect {
        CGRect(
            x: attributes.frame.origin.x - wireframeRect.origin.x,
            y: attributes.frame.origin.y - wireframeRect.origin.y,
            width: max(wireframeRect.width, attributes.frame.width),
            height: max(wireframeRect.height, attributes.frame.height)
        )
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: relativeIntersectedRect,
                text: textObfuscator.mask(text: text),
                clip: clip,
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
