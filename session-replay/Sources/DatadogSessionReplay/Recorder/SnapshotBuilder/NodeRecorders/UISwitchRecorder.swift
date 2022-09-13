/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal struct UISwitchRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard let `switch` = view as? UISwitch else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let builder = UISwitchWireframesBuilder(
            attributes: attributes,
            isOn: `switch`.isOn,
            thumbTintColor: `switch`.thumbTintColor?.cgColor,
            onTintColor: `switch`.onTintColor?.cgColor,
            offTintColor: `switch`.tintColor?.cgColor
        )
        return SpecificElement(wireframesBuilder: builder)
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

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let radius = attributes.frame.height * 0.5
        let backgroundColor = isOn ? (onTintColor ?? SystemDefaults.onTintColor) : (offTintColor ?? SystemDefaults.offTintColor)

        let background = builder.createShapeWireframe(
            frame: attributes.frame,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: backgroundColor,
            cornerRadius: radius,
            opacity: attributes.alpha
        )

        let thumbFrame = CGRect(
            x: attributes.frame.minX + (isOn ? radius : 0.0),
            y: attributes.frame.minY,
            width: radius * 2,
            height: attributes.frame.height
        )

        let thumb = builder.createShapeWireframe(
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
