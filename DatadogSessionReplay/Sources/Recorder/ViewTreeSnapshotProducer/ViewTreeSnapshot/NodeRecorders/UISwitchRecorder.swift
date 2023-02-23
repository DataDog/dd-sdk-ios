/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UISwitchRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let `switch` = view as? UISwitch else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(2, for: `switch`)

        let builder = UISwitchWireframesBuilder(
            backgroundWireframeID: ids[0],
            thumbWireframeID: ids[1],
            attributes: attributes,
            isOn: `switch`.isOn,
            thumbTintColor: `switch`.thumbTintColor?.cgColor,
            onTintColor: `switch`.onTintColor?.cgColor,
            offTintColor: `switch`.tintColor?.cgColor,
            wireframeRect: attributes.frame
        )
        return SpecificElement(wireframesBuilder: builder, recordSubtree: false)
    }
}

internal struct UISwitchWireframesBuilder: NodeWireframesBuilder {
    struct SystemDefaults {
        /// Default color of the thumb.
        static let thumbTintColor: CGColor = UIColor.white.cgColor
        /// Default color of the background in "on" state.
        static let onTintColor: CGColor = UIColor.systemGreen.cgColor
        /// Default color of the background in "off" state.
        static let offTintColor: CGColor = UIColor.lightGray.cgColor
    }

    let backgroundWireframeID: WireframeID
    let thumbWireframeID: WireframeID
    /// Attributes of the base `UIView`.
    let attributes: ViewAttributes
    /// If the switch is "on" or "off".
    let isOn: Bool
    /// The custom color of the thumb.
    let thumbTintColor: CGColor?
    /// The custom color of the background in "on" state.
    let onTintColor: CGColor?
    /// The custom color of the background in "off" state.
    let offTintColor: CGColor?

    let wireframeRect: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let radius = attributes.frame.height * 0.5
        let backgroundColor = isOn ? (onTintColor ?? SystemDefaults.onTintColor) : (offTintColor ?? SystemDefaults.offTintColor)

        let background = builder.createShapeWireframe(
            id: backgroundWireframeID,
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: backgroundColor,
            cornerRadius: radius,
            opacity: attributes.alpha
        )

        let thumbFrame = CGRect(
            x: wireframeRect.minX + (isOn ? radius : 0.0),
            y: wireframeRect.minY,
            width: radius * 2,
            height: attributes.frame.height
        )

        let thumb = builder.createShapeWireframe(
            id: thumbWireframeID,
            frame: thumbFrame,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: thumbTintColor ?? SystemDefaults.thumbTintColor,
            cornerRadius: radius,
            opacity: attributes.alpha
        )

        return [background, thumb]
    }
}
