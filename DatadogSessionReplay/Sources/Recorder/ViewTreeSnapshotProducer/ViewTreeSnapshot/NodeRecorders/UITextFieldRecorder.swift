/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UITextFieldRecorder: NodeRecorder {
    /// `UIViewRecorder` for recording appearance of the text field.
    private let backgroundViewRecorder: UIViewRecorder
    /// `UIImageViewRecorder` for recording icons that are displayed in text field.
    private let iconsRecorder: UIImageViewRecorder
    private let subtreeRecorder: ViewTreeRecorder

    var textObfuscator: (ViewTreeRecordingContext, _ isSensitive: Bool, _ isPlaceholder: Bool) -> TextObfuscating = { context, isSensitive, isPlaceholder in
        if isPlaceholder {
            return context.recorder.privacy.hintTextObfuscator
        } else if isSensitive {
            return context.recorder.privacy.sensitiveTextObfuscator
        } else {
            return context.recorder.privacy.inputAndOptionTextObfuscator
        }
    }

    init() {
        self.backgroundViewRecorder = UIViewRecorder()
        self.iconsRecorder = UIImageViewRecorder()
        self.subtreeRecorder = ViewTreeRecorder(nodeRecorders: [backgroundViewRecorder, iconsRecorder])
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let textField = view as? UITextField else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        // For our "approximation", we render text field's text on top of other TF's appearance.
        // Here we record both kind of nodes separately and order them respectively in returned semantics:
        let appearanceNodes = recordAppearance(in: textField, textFieldAttributes: attributes, using: context)
        if let textNode = recordText(in: textField, attributes: attributes, using: context) {
            return SpecificElement(subtreeStrategy: .ignore, nodes: appearanceNodes + [textNode])
        } else {
            return SpecificElement(subtreeStrategy: .ignore, nodes: appearanceNodes)
        }
    }

    /// Records `UIView` and `UIImageViewRecorder` nodes that define text field's appearance.
    private func recordAppearance(in textField: UITextField, textFieldAttributes: ViewAttributes, using context: ViewTreeRecordingContext) -> [Node] {
        backgroundViewRecorder.semanticsOverride = { _, viewAttributes in
            // We consider view to define text field's appearance if it has the same
            // size as text field:
            let hasSameSize = textFieldAttributes.frame == viewAttributes.frame
            let isBackground = hasSameSize && viewAttributes.hasAnyAppearance
            return !isBackground ? IgnoredElement(subtreeStrategy: .record) : nil
        }

        return subtreeRecorder.recordNodes(for: textField, in: context)
    }

    /// Creates node that represents TF's text.
    /// We cannot use general view-tree traversal solution to find nested labels (`UITextField's` subtree doesn't look that way). Instead, we read
    /// text information and create arbitrary node with appropriate wireframes builder configuration.
    private func recordText(in textField: UITextField, attributes: ViewAttributes, using context: ViewTreeRecordingContext) -> Node? {
        let text: String
        let isPlaceholder: Bool

        if let fieldText = textField.text, !fieldText.isEmpty {
            text = fieldText
            isPlaceholder = false
        } else if let fieldPlaceholder = textField.placeholder {
            text = fieldPlaceholder
            isPlaceholder = true
        } else {
            return nil
        }

        let textFrame = attributes.frame
            .insetBy(dx: 5, dy: 5) // 5 points padding

        let builder = UITextFieldWireframesBuilder(
            wireframeRect: textFrame,
            attributes: attributes,
            wireframeID: context.ids.nodeID(for: textField),
            text: text,
            textColor: textField.textColor?.cgColor,
            textAlignment: textField.textAlignment,
            isPlaceholderText: isPlaceholder,
            font: textField.font,
            fontScalingEnabled: textField.adjustsFontSizeToFitWidth,
            textObfuscator: textObfuscator(context, textField.isSensitiveText, isPlaceholder)
        )
        return Node(viewAttributes: attributes, wireframesBuilder: builder)
    }
}

internal struct UITextFieldWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect
    let attributes: ViewAttributes

    let wireframeID: WireframeID

    let text: String
    let textColor: CGColor?
    let textAlignment: NSTextAlignment
    let isPlaceholderText: Bool
    let font: UIFont?
    let fontScalingEnabled: Bool
    let textObfuscator: TextObfuscating

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: wireframeRect,
                text: textObfuscator.mask(text: text),
                textFrame: wireframeRect,
                textAlignment: .init(systemTextAlignment: textAlignment),
                textColor: isPlaceholderText ? SystemColors.placeholderText : textColor,
                font: font,
                fontScalingEnabled: fontScalingEnabled,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
