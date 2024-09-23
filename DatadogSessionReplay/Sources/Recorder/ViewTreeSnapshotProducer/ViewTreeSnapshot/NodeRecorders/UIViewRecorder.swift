/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal class UIViewRecorder: NodeRecorder {
    internal let identifier: UUID

    /// An option for overriding default semantics from parent recorder.
    var semanticsOverride: (UIView, ViewAttributes) -> NodeSemantics?

    init(
        identifier: UUID,
        semanticsOverride: @escaping (UIView, ViewAttributes) -> NodeSemantics? = { _, _ in nil }
    ) {
        self.identifier = identifier
        self.semanticsOverride = semanticsOverride
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        var attributes = attributes
        if context.viewControllerContext.isRootView(of: .alert) {
            attributes = attributes.copy {
                $0.backgroundColor = SystemColors.systemBackground
                $0.layerBorderColor = nil
                $0.layerBorderWidth = 0
                $0.layerCornerRadius = 16
                $0.alpha = 1
                $0.isHidden = false
            }
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }
        if let semantics = semanticsOverride(view, attributes) {
            return semantics
        }

        if attributes.sessionReplayOverride?.hidden == true {
            let builder = UIViewWireframesBuilder(
                wireframeID: context.ids.nodeID(view: view, nodeRecorder: self),
                attributes: attributes
            )
            let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
            return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
        }

        guard attributes.hasAnyAppearance else {
            // The view has no appearance, but it may contain subviews that bring visual elements, so
            // we use `InvisibleElement` semantics (to drop it) with `.record` strategy for its subview.
            return InvisibleElement(subtreeStrategy: .record)
        }

        let builder = UIViewWireframesBuilder(
            wireframeID: context.ids.nodeID(view: view, nodeRecorder: self),
            attributes: attributes
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return AmbiguousElement(nodes: [node])
    }
}

internal struct UIViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// Attributes of the `UIView`.
    let attributes: ViewAttributes

    var wireframeRect: CGRect {
        attributes.frame
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        if attributes.sessionReplayOverride?.hidden == true {
            return [
                builder.createPlaceholderWireframe(id: wireframeID, frame: wireframeRect, label: "Hidden")
            ]
        }
        return [
            builder.createShapeWireframe(id: wireframeID, frame: wireframeRect, attributes: attributes)
        ]
    }
}
#endif
