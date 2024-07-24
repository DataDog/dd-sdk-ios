/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UISwitchRecorder: NodeRecorder {
    internal let identifier: UUID

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let `switch` = view as? UISwitch else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        // The actual frame of the switch. It might be different than `view.frame` if displayed in stack view:
        let switchFrame = CGRect(origin: attributes.frame.origin, size: view.intrinsicContentSize)
        let ids = context.ids.nodeIDs(3, view: `switch`, nodeRecorder: self)

        let builder = UISwitchWireframesBuilder(
            wireframeRect: switchFrame,
            attributes: attributes,
            backgroundWireframeID: ids[0],
            trackWireframeID: ids[1],
            thumbWireframeID: ids[2],
            isEnabled: `switch`.isEnabled,
            isDarkMode: `switch`.usesDarkMode,
            isOn: `switch`.isOn,
            isMasked: context.recorder.privacy.shouldMaskInputElements,
            thumbTintColor: `switch`.thumbTintColor?.cgColor,
            onTintColor: `switch`.onTintColor?.cgColor,
            offTintColor: `switch`.tintColor?.cgColor
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UISwitchWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect
    let attributes: ViewAttributes

    let backgroundWireframeID: WireframeID
    let trackWireframeID: WireframeID
    let thumbWireframeID: WireframeID
    let isEnabled: Bool
    let isDarkMode: Bool
    let isOn: Bool
    let isMasked: Bool
    let thumbTintColor: CGColor?
    let onTintColor: CGColor?
    let offTintColor: CGColor?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        if isMasked {
            return createMasked(with: builder)
        } else {
            return createNotMasked(with: builder)
        }
    }

    private func createMasked(with builder: WireframesBuilder) -> [SRWireframe] {
        let track = builder.createShapeWireframe(
            id: trackWireframeID,
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: SystemColors.tertiarySystemFill,
            cornerRadius: wireframeRect.height * 0.5,
            opacity: isEnabled ? attributes.alpha : 0.5
        )

        // Create background wireframe if the underlying `UIView` has any appearance:
        if attributes.hasAnyAppearance {
            let background = builder.createShapeWireframe(id: backgroundWireframeID, frame: attributes.frame, attributes: attributes)

            return [background, track]
        } else {
            return [track]
        }
    }

    private func createNotMasked(with builder: WireframesBuilder) -> [SRWireframe] {
        let radius = wireframeRect.height * 0.5

        // Create track wireframe:
        let trackColor = isOn ? (onTintColor ?? SystemColors.systemGreen) : (offTintColor ?? SystemColors.tertiarySystemFill)
        let track = builder.createShapeWireframe(
            id: trackWireframeID,
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: trackColor,
            cornerRadius: radius,
            opacity: isEnabled ? attributes.alpha : 0.5
        )

        // Create thumb wireframe:
        let thumbContainer = wireframeRect.insetBy(dx: 2, dy: 2)
        let thumbFrame = CGRect(origin: .zero, size: .init(width: thumbContainer.height, height: thumbContainer.height))
            .putInside(thumbContainer, horizontalAlignment: isOn ? .right : .left, verticalAlignment: .middle)
        let thumb = builder.createShapeWireframe(
            id: thumbWireframeID,
            frame: thumbFrame,
            borderColor: SystemColors.secondarySystemFill,
            borderWidth: 1,
            backgroundColor: thumbTintColor ?? ((isDarkMode && !isEnabled) ? UIColor.gray.cgColor : UIColor.white.cgColor),
            cornerRadius: radius
        )

        // Create background wireframe if the underlying `UIView` has any appearance:
        if attributes.hasAnyAppearance {
            let background = builder.createShapeWireframe(id: backgroundWireframeID, frame: attributes.frame, attributes: attributes)

            return [background, track, thumb]
        } else {
            return [track, thumb]
        }
    }
}
#endif
