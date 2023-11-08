/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal class UILabelRecorder: NodeRecorder {
    let identifier = UUID()

    /// An option for customizing wireframes builder created by this recorder.
    var builderOverride: (UILabelWireframesBuilder) -> UILabelWireframesBuilder
    var textObfuscator: (ViewTreeRecordingContext) -> TextObfuscating

    init(
        builderOverride: @escaping (UILabelWireframesBuilder) -> UILabelWireframesBuilder = { $0 },
        textObfuscator: @escaping (ViewTreeRecordingContext) -> TextObfuscating = { context in
            return context.recorder.privacy.staticTextObfuscator
        }
    ) {
        self.builderOverride = builderOverride
        self.textObfuscator = textObfuscator
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let label = view as? UILabel else {
            return nil
        }

        let hasVisibleText = attributes.isVisible && !(label.text?.isEmpty ?? true)

        guard hasVisibleText || attributes.hasAnyAppearance else {
            return InvisibleElement.constant
        }

        let builder = UILabelWireframesBuilder(
            wireframeID: context.ids.nodeID(view: label, nodeRecorder: self),
            attributes: attributes,
            text: label.text ?? "",
            textColor: label.textColor?.cgColor,
            textAlignment: label.textAlignment,
            font: label.font,
            fontScalingEnabled: label.adjustsFontSizeToFitWidth,
            textObfuscator: textObfuscator(context)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builderOverride(builder))
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UILabelWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// The text inside label.
    let text: String
    /// The color of the text.
    var textColor: CGColor?
    /// The alignment of the text.
    var textAlignment: NSTextAlignment
    /// The font used by the label.
    let font: UIFont?
    /// Flag that determines if font should be scaled
    var fontScalingEnabled: Bool
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating

    var wireframeRect: CGRect {
        attributes.frame
    }

    func buildWireframes(with builder: WireframesBuilder) -> [Wireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: wireframeRect,
                text: textObfuscator.mask(text: text),
                textAlignment: .init(systemTextAlignment: textAlignment),
                textColor: textColor,
                font: font,
                fontScalingEnabled: fontScalingEnabled,
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
