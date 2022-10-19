/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal struct UITextFieldRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard let textField = view as? UITextField else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        // TODO: RUMM-2459
        // Explore other (better) ways of infering text field appearance:

        var editorProperties: UITextFieldWireframesBuilder.EditorFieldProperties? = nil
        // Lookup the actual editor field's view in `textField` hierarchy to infer its appearance.
        // Perhaps this can be do better by infering it from `UITextField` object in RUMM-2459:
        dfsVisitSubviews(of: textField) { subview in
            if subview.bounds == textField.bounds {
                editorProperties = .init(
                    backgroundColor: subview.backgroundColor?.cgColor,
                    layerBorderColor: subview.layer.borderColor,
                    layerBorderWidth: subview.layer.borderWidth,
                    layerCornerRadius: subview.layer.cornerRadius
                )
            }
        }

        let text: String = {
            guard let textFieldText = textField.text, !textFieldText.isEmpty else {
                return textField.placeholder ?? ""
            }
            return textFieldText
        }()

        let builder = UITextFieldWireframesBuilder(
            wireframeID: context.ids.nodeID(for: textField),
            attributes: attributes,
            text: text,
            // TODO: RUMM-2459
            // Is it correct to assume `textField.textColor` for placeholder text?
            textColor: textField.textColor?.cgColor,
            font: textField.font,
            editor: editorProperties,
            textObfuscator: context.options.privacy == .maskAll ? context.textObfuscator : nopTextObfuscator
        )
        return SpecificElement(wireframesBuilder: builder)
    }
}

internal struct UITextFieldWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside text field.
    let text: String
    /// The color of the text.
    let textColor: CGColor?
    /// The font used by the text field.
    let font: UIFont?
    /// Properties of the editor field (which is a nested subview in `UITextField`).
    let editor: EditorFieldProperties?
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating

    struct EditorFieldProperties {
        /// Editor view's `.backgorundColor`.
        var backgroundColor: CGColor? = nil
        /// Editor view's `layer.backgorundColor`.
        var layerBorderColor: CGColor? = nil
        /// Editor view's `layer.backgorundColor`.
        var layerBorderWidth: CGFloat = 0
        /// Editor view's `layer.cornerRadius`.
        var layerCornerRadius: CGFloat = 0
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        // TODO: RUMM-2459
        // Enhance text fields rendering by calculating the actual frame of the text:
        let textFrame = attributes.frame

        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: attributes.frame,
                text: textObfuscator.mask(text: text),
                textFrame: textFrame,
                textColor: textColor,
                font: font,
                borderColor: editor?.layerBorderColor ?? attributes.layerBorderColor,
                borderWidth: editor?.layerBorderWidth ?? attributes.layerBorderWidth,
                backgroundColor: editor?.backgroundColor ?? attributes.backgroundColor,
                cornerRadius: editor?.layerCornerRadius ?? attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}

private func dfsVisitSubviews(of view: UIView, visit: (UIView) -> Void) {
    view.subviews.forEach { subview in
        visit(subview)
        dfsVisitSubviews(of: subview, visit: visit)
    }
}
