/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UIStepperRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let stepper = view as? UIStepper else {
            return nil
        }
        
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let stepperFrame = CGRect(origin: attributes.frame.origin, size: stepper.intrinsicContentSize)
        let ids = context.ids.nodeIDs(4, for: stepper)

        let builder = UIStepperWireframesBuilder(
            wireframeRect: stepperFrame,
            cornerRadius: stepper.subviews.first?.layer.cornerRadius ?? 0,
            ids: ids
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UIStepperWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect
    var cornerRadius: CGFloat
    var ids: [Int64]

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let background = builder.createShapeWireframe(
            id: ids[0],
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: SystemColors.tertiarySystemBackground,
            cornerRadius: cornerRadius
        )
        let divider = builder.createShapeWireframe(
            id: ids[1],
            frame: CGRect(
                origin: CGPoint(x: wireframeRect.origin.x + 46.5, y: wireframeRect.origin.y + 6),
                size: CGSize(width: 1, height: 20)
            ),
            backgroundColor: SystemColors.placeholderText
        )
        let stepButtonFontSize = CGFloat(30)
        let stepButtonSize = CGSize(width: stepButtonFontSize, height: stepButtonFontSize)
        let stepButtonLeftOffset = wireframeRect.width / 2 - stepButtonSize.width / 2
        let minus = builder.createTextWireframe(
            id: ids[2],
            frame: CGRect(
                origin: CGPoint(
                    x: wireframeRect.origin.x + stepButtonLeftOffset,
                    y: wireframeRect.origin.y
                ),
                size: stepButtonSize
            ),
            text: "-",
            textColor: SystemColors.label,
            font: .systemFont(ofSize: stepButtonFontSize)
        )
        let plus = builder.createTextWireframe(
            id: ids[3],
            frame: CGRect(
                origin: CGPoint(
                    x: wireframeRect.origin.x + wireframeRect.width / 2 + stepButtonLeftOffset,
                    y: wireframeRect.origin.y
                ),
                size: stepButtonSize
            ),
            text: "+",
            textColor: SystemColors.label,
            font: .systemFont(ofSize: stepButtonFontSize)
        )
        return [background, divider, minus, plus]
    }
}
