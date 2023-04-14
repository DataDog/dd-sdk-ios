/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UITextViewRecorder: NodeRecorder {
    var textObfuscator: (ViewTreeRecordingContext, _ isSensitiveText: Bool) -> TextObfuscating = { context, isSensitiveText in
        if isSensitiveText {
            return context.textObfuscators.fixLegthMask
        }

        switch context.recorder.privacy {
        case .allowAll:         return context.textObfuscators.nop
        case .maskAll:          return context.textObfuscators.spacePreservingMask
        case .maskUserInput:    return context.textObfuscators.spacePreservingMask
        }
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let textView = view as? UITextView else {
            return nil
        }
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let isSensitiveText = textView.isSecureTextEntry || textView.textContentType == .emailAddress || textView.textContentType == .telephoneNumber

        let builder = UITextViewWireframesBuilder(
            wireframeID: context.ids.nodeID(for: textView),
            attributes: attributes,
            text: textView.text,
            textAlignment: .init(textAlignment: textView.textAlignment),
            textColor: textView.textColor?.cgColor ?? UIColor.black.cgColor,
            font: textView.font,
            textObfuscator: textObfuscator(context, isSensitiveText),
            contentRect: CGRect(origin: textView.contentOffset, size: textView.contentSize)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }
}

internal struct UITextViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside text field.
    let text: String
    /// The alignment of the text.
    var textAlignment: SRTextPosition.Alignment
    /// The color of the text.
    let textColor: CGColor?
    /// The font used by the text field.
    let font: UIFont?
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating
    /// The frame of the text content
    let contentRect: CGRect

    var wireframeRect: CGRect {
        attributes.frame
    }

    private var clip: SRContentClip {
        let top = abs(contentRect.origin.y)
        let left = abs(contentRect.origin.x)
        let bottom = max(contentRect.height - attributes.frame.height - top, 0)
        let right = max(contentRect.width - attributes.frame.width - left, 0)
        return SRContentClip(
            bottom: Int64(withNoOverflow: bottom),
            left: Int64(withNoOverflow: left),
            right: Int64(withNoOverflow: right),
            top: Int64(withNoOverflow: top)
        )
    }

    private var relativeIntersectedRect: CGRect {
        CGRect(
            x: attributes.frame.origin.x - contentRect.origin.x,
            y: attributes.frame.origin.y - contentRect.origin.y,
            width: max(contentRect.width, attributes.frame.width),
            height: max(contentRect.height, attributes.frame.height)
        )
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: relativeIntersectedRect,
                text: textObfuscator.mask(text: text),
                textAlignment: textAlignment,
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
