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
        let verticalMargin: CGFloat = 6
        let divider = builder.createShapeWireframe(
            id: ids[1],
            frame: CGRect(
                origin: CGPoint(x: 0, y: verticalMargin),
                size: CGSize(width: 1, height: wireframeRect.size.height - 2 * verticalMargin)
            ).putInside(wireframeRect, horizontalAlignment: .center, verticalAlignment: .middle),
            backgroundColor: SystemColors.placeholderText
        )

        let horizontalElementRect = CGRect(origin: .zero, size: CGSize(width: 14, height: 2))
        let verticalElementRect = CGRect(origin: .zero, size: CGSize(width: 2, height: 14))
        let leftButtonFrame = CGRect(
            origin: wireframeRect.origin,
            size: CGSize(width: wireframeRect.size.width / 2, height: wireframeRect.size.height)
        )
        let rightButtonFrame = CGRect(
            origin: CGPoint(x: wireframeRect.origin.x + wireframeRect.size.width / 2, y: wireframeRect.origin.y),
            size: CGSize(width: wireframeRect.size.width / 2, height: wireframeRect.size.height)
        )
        let minus = builder.createShapeWireframe(
            id: ids[2],
            frame: horizontalElementRect.putInside(leftButtonFrame, horizontalAlignment: .center, verticalAlignment: .middle),
            backgroundColor: isMinusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: horizontalElementRect.size.height
        )
        let plusHorizontal = builder.createShapeWireframe(
            id: ids[3],
            frame: horizontalElementRect.putInside(rightButtonFrame, horizontalAlignment: .center, verticalAlignment: .middle),
            backgroundColor: isPlusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: horizontalElementRect.size.height
        )
        let plusVertical = builder.createShapeWireframe(
            id: ids[4],
            frame: verticalElementRect.putInside(rightButtonFrame, horizontalAlignment: .center, verticalAlignment: .middle),
            backgroundColor: isPlusEnabled ? SystemColors.label : SystemColors.placeholderText,
            cornerRadius: verticalElementRect.size.width
        )
        return [background, divider, minus, plusHorizontal, plusVertical]
    }
}
