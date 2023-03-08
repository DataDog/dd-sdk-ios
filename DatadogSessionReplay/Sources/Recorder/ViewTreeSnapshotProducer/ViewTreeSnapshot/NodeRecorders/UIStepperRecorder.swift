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
        let ids = context.ids.nodeIDs(5, for: stepper)

        let builder = UIStepperWireframesBuilder(
            wireframeRect: stepperFrame,
            cornerRadius: stepper.subviews.first?.layer.cornerRadius ?? 0,
            ids: ids,
            isMinusEnabled: stepper.value > stepper.minimumValue,
            isPlusEnabled: stepper.value < stepper.maximumValue
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UIStepperWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect
    let cornerRadius: CGFloat
    let ids: [Int64]
    let isMinusEnabled: Bool
    let isPlusEnabled: Bool

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let background = builder.createShapeWireframe(
            id: ids[0],
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: SystemColors.tertiarySystemFill,
            cornerRadius: cornerRadius
        )
        let divider = builder.createShapeWireframe(
            id: ids[1],
            frame: CGRect(
                origin: CGPoint(x: wireframeRect.origin.x + wireframeRect.size.width / 2, y: wireframeRect.origin.y + 6),
                size: CGSize(width: 1, height: 20)
            ),
            backgroundColor: SystemColors.placeholderText
        )


        let horizontalElementSize = CGSize(width: 15, height: 1.5)
        let verticalElementSize = CGSize(width: 1.5, height: 15)
        let horizontalLeftOffset: CGFloat = wireframeRect.size.width / 4 - horizontalElementSize.width / 2
        let verticalLeftOffset: CGFloat = horizontalLeftOffset + horizontalElementSize.width / 2 - verticalElementSize.width / 2

        let minus = builder.createShapeWireframe(
            id: ids[2],
            frame: CGRect(
                origin: CGPoint(
                    x: wireframeRect.origin.x + horizontalLeftOffset,
                    y: wireframeRect.origin.y + wireframeRect.height / 2 - horizontalElementSize.height
                ),
                size: horizontalElementSize
            ),
            backgroundColor: isMinusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: horizontalElementSize.height
        )
        let plusHorizontal = builder.createShapeWireframe(
            id: ids[3],
            frame: CGRect(
                origin: CGPoint(
                    x: wireframeRect.origin.x + wireframeRect.width / 2 + horizontalLeftOffset - 0.5,
                    y: wireframeRect.origin.y + wireframeRect.height / 2 - horizontalElementSize.height
                ),
                size: horizontalElementSize
            ),
            backgroundColor: isPlusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: horizontalElementSize.height
        )
        let plusVertical = builder.createShapeWireframe(
            id: ids[4],
            frame: CGRect(
                origin: CGPoint(
                    x: wireframeRect.origin.x + wireframeRect.width / 2 + verticalLeftOffset,
                    y: wireframeRect.origin.y + wireframeRect.height / 2 - verticalElementSize.height / 2 + 0.5
                ),
                size: verticalElementSize
            ),
            backgroundColor: isPlusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: verticalElementSize.width
        )
        return [background, divider, minus, plusHorizontal, plusVertical]
    }
}
