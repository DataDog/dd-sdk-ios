/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UITextViewRecorder: NodeRecorder {
    let identifier = UUID()

    var textObfuscator: (ViewTreeRecordingContext, _ isSensitive: Bool, _ isEditable: Bool) -> TextObfuscating = { context, isSensitive, isEditable in
        if isSensitive {
            return context.recorder.privacy.sensitiveTextObfuscator
        }

        if isEditable {
            return context.recorder.privacy.inputAndOptionTextObfuscator
        } else {
            return context.recorder.privacy.staticTextObfuscator
        }
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let textView = view as? UITextView else {
            return nil
        }
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let builder = UITextViewWireframesBuilder(
            wireframeID: context.ids.nodeID(view: textView, nodeRecorder: self),
            attributes: attributes,
            text: textView.text,
            textAlignment: textView.textAlignment,
            textColor: textView.textColor?.cgColor ?? UIColor.black.cgColor,
            font: textView.font,
            textObfuscator: textObfuscator(context, textView.isSensitiveText, textView.isEditable),
            contentRect: CGRect(origin: textView.contentOffset, size: textView.contentSize)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UITextViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside text field.
    let text: String
    /// The alignment of the text.
    var textAlignment: NSTextAlignment
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
        // UITextView adds additional padding for presented content.
        let padding: CGFloat = 8
        return CGRect(
            x: attributes.frame.origin.x - contentRect.origin.x + padding,
            y: attributes.frame.origin.y - contentRect.origin.y + padding,
            width: max(contentRect.width, attributes.frame.width) - padding,
            height: max(contentRect.height, attributes.frame.height) - padding
        )
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: relativeIntersectedRect,
                text: textObfuscator.mask(text: text),
                textAlignment: .init(systemTextAlignment: textAlignment, vertical: .top),
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
#endif
