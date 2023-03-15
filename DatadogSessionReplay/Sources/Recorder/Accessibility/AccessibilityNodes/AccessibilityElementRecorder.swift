/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Accessibility

internal class AccessibilityElementRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard view.isAccessibilityElement else {
            return nil
        }

        let ids = context.accessibilityIDs.nodeIDs(2, for: view)

        if let accessibilityLabel = view.accessibilityLabel {
            let builder = GoodAccessibilityElementWireframesBuilder(
                ids: (ids[0], ids[1]),
                attributes: attributes,
                wireframeRect: view.accessibilityFrame,
                accessibilityLabel: accessibilityLabel,
                textObfuscator: context.textObfuscator
            )
            let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
            return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
        } else {
            let builder = BadAccessibilityElementWireframesBuilder(
                ids: (ids[0], ids[1]),
                attributes: attributes,
                wireframeRect: view.accessibilityFrame
            )
            let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
            return SpecificElement(subtreeStrategy: .record, nodes: [node])
        }
    }
}

internal struct GoodAccessibilityElementWireframesBuilder: NodeWireframesBuilder {
    let ids: (WireframeID, WireframeID)
    var wireframeID: WireframeID { ids.0 }
    let attributes: ViewAttributes
    let wireframeRect: CGRect

    let accessibilityLabel: String
    let textObfuscator: TextObfuscating

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return builder.createAccessibilityWireframes(
            ids: ids,
            frame: wireframeRect,
            color: .green,
            annotationText: nil,
            borderWidth: 2,
            cornerRadius: attributes.layerCornerRadius
        )
    }
}

internal struct BadAccessibilityElementWireframesBuilder: NodeWireframesBuilder {
    let ids: (WireframeID, WireframeID)
    var wireframeID: WireframeID { ids.0 }
    let attributes: ViewAttributes
    let wireframeRect: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return builder.createAccessibilityWireframes(
            ids: ids,
            frame: wireframeRect,
            color: .red,
            annotationText: nil,
            borderWidth: 2,
            cornerRadius: attributes.layerCornerRadius
        )
    }
}

extension WireframesBuilder {
    func createAccessibilityWireframes(
        ids: (WireframeID, WireframeID),
        frame: CGRect,
        color: UIColor,
        annotationText: String?,
        borderWidth: CGFloat,
        cornerRadius: CGFloat
    ) -> [SRWireframe] {
        var wireframes: [SRWireframe] = []

        let border = createShapeWireframe(
            id: ids.0,
            frame: frame,
            borderColor: color.cgColor,
            borderWidth: borderWidth,
            backgroundColor: nil,
            cornerRadius: cornerRadius
        )
        wireframes.append(border)

        if let text = annotationText.map({ NSString(string: $0) }) {
            let font = UIFont.systemFont(ofSize: 14)
            let textSize = text.size(withAttributes: [.font: font])
            let textFrame = CGRect(x: frame.minX, y: frame.minY - textSize.height - 3, width: textSize.width, height: textSize.height)
                .insetBy(dx: -2, dy: -2)

            let annotation = createTextWireframe(
                id: ids.1,
                frame: textFrame,
                text: text as String,
                textFrame: textFrame,
                textAlignment: .init(horizontal: .center, vertical: .center),
                textColor: UIColor.white.cgColor,
                font: font,
                backgroundColor: color.cgColor
            )
            wireframes.append(annotation)
        }

        return wireframes
    }
}
