/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UISliderRecorder: NodeRecorder {
    let identifier = UUID()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let slider = view as? UISlider else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let span = startSpan()
        defer { span.end() }

        let ids = context.ids.nodeIDs(4, view: slider, nodeRecorder: self)

        let builder = UISliderWireframesBuilder(
            wireframeRect: attributes.frame,
            attributes: attributes,
            backgroundWireframeID: ids[0],
            minTrackWireframeID: ids[1],
            maxTrackWireframeID: ids[2],
            thumbWireframeID: ids[3],
            value: (min: slider.minimumValue, max: slider.maximumValue, current: slider.value),
            isEnabled: slider.isEnabled,
            isMasked: context.recorder.privacy.shouldMaskInputElements,
            minTrackTintColor: slider.minimumTrackTintColor?.cgColor ?? slider.tintColor?.cgColor,
            maxTrackTintColor: slider.maximumTrackTintColor?.cgColor,
            thumbTintColor: slider.thumbTintColor?.cgColor
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UISliderWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect
    let attributes: ViewAttributes

    let backgroundWireframeID: WireframeID
    let minTrackWireframeID: WireframeID
    let maxTrackWireframeID: WireframeID
    let thumbWireframeID: WireframeID
    let value: (min: Float, max: Float, current: Float)
    let isEnabled: Bool
    let isMasked: Bool
    let minTrackTintColor: CGColor?
    let maxTrackTintColor: CGColor?
    let thumbTintColor: CGColor?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        if isMasked {
            return createMasked(with: builder)
        } else {
            return createNotMasked(with: builder)
        }
    }

    private func createMasked(with builder: WireframesBuilder) -> [SRWireframe] {
        let trackFrame = wireframeRect.divided(atDistance: 3, from: .minYEdge)
            .slice
            .putInside(wireframeRect, horizontalAlignment: .left, verticalAlignment: .middle)

        let track = builder.createShapeWireframe(
            id: minTrackWireframeID,
            frame: trackFrame,
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
        guard value.max > value.min else {
            return [] // illegal, should not happen
        }

        let normalValue = CGFloat((value.current - value.min) / (value.max - value.min)) // normalized, 0 to 1
        let (left, right) = wireframeRect
            .divided(atDistance: normalValue * wireframeRect.width, from: .minXEdge)

        // Create thumb wireframe:
        let radius = wireframeRect.height * 0.5
        let thumbFrame = CGRect(x: left.maxX, y: left.minY, width: wireframeRect.height, height: wireframeRect.height)
            .offsetBy(dx: -radius, dy: 0)

        let thumb = builder.createShapeWireframe(
            id: thumbWireframeID,
            frame: thumbFrame,
            borderColor: isEnabled ? SystemColors.secondarySystemFill : SystemColors.tertiarySystemFill,
            borderWidth: 1,
            backgroundColor: isEnabled ? (thumbTintColor ?? UIColor.white.cgColor) : SystemColors.tertiarySystemBackground,
            cornerRadius: radius,
            opacity: attributes.alpha
        )

        // Create min track wireframe:
        let leftTrackFrame = left.divided(atDistance: 3, from: .minYEdge)
            .slice
            .putInside(left, horizontalAlignment: .left, verticalAlignment: .middle)

        let leftTrack = builder.createShapeWireframe(
            id: minTrackWireframeID,
            frame: leftTrackFrame,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: minTrackTintColor ?? SystemColors.tintColor,
            cornerRadius: 0,
            opacity: isEnabled ? attributes.alpha : 0.5
        )

        // Create max track wireframe:
        let rightTrackFrame = right.divided(atDistance: 3, from: .minYEdge)
            .slice
            .putInside(right, horizontalAlignment: .left, verticalAlignment: .middle)

        let rightTrack = builder.createShapeWireframe(
            id: maxTrackWireframeID,
            frame: rightTrackFrame,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: maxTrackTintColor ?? SystemColors.tertiarySystemFill,
            cornerRadius: 0,
            opacity: isEnabled ? attributes.alpha : 0.5
        )

        if attributes.hasAnyAppearance {
            // Create background wireframe only if view declares visible background
            let background = builder.createShapeWireframe(id: backgroundWireframeID, frame: wireframeRect, attributes: attributes)

            return [background, leftTrack, rightTrack, thumb]
        } else {
            return [leftTrack, rightTrack, thumb]
        }
    }
}
#endif
