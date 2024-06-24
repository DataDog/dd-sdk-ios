/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIProgressViewRecorder: NodeRecorder {
    let identifier = UUID()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let progressView = view as? UIProgressView else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(2, view: progressView, nodeRecorder: self)

        let builder = UIProgressViewWireframesBuilder(
            wireframeRect: attributes.frame,
            attributes: attributes,
            backgroundWireframeID: ids[0],
            progressTrackWireframeID: ids[1],
            progress: progressView.progress,
            progressTintColor: progressView.progressTintColor?.cgColor ?? progressView.tintColor.cgColor,
            backgroundColor: progressView.trackTintColor?.cgColor ?? progressView.backgroundColor?.cgColor
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UIProgressViewWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect
    let attributes: ViewAttributes

    let backgroundWireframeID: WireframeID
    let progressTrackWireframeID: WireframeID
    let progress: Float
    let progressTintColor: CGColor
    let backgroundColor: CGColor?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        guard progress >= 0 && progress <= 1 else {
            return [] // illegal, should not happen
        }

        let background = builder.createShapeWireframe(
            id: backgroundWireframeID,
            frame: wireframeRect, 
            backgroundColor: backgroundColor ?? SystemColors.tertiarySystemFill,
            cornerRadius: wireframeRect.height/2
        )

        // Create progress wireframe
        let (progressRect, _) = wireframeRect
            .divided(atDistance: CGFloat(progress) * wireframeRect.width, from: .minXEdge)
        let progressTrackFrame = progressRect.putInside(wireframeRect, horizontalAlignment: .left, verticalAlignment: .middle)

        let progressTrack = builder.createShapeWireframe(
            id: progressTrackWireframeID,
            frame: progressTrackFrame,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: progressTintColor,
            cornerRadius: wireframeRect.height/2,
            opacity: attributes.alpha
        )

        return [background, progressTrack]
    }
}
#endif
