/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit
import SwiftUI

internal struct UnsupportedViewRecorder: NodeRecorder {
    internal let identifier: UUID

    init(identifier: UUID) {
        self.identifier = identifier
    }

    // swiftlint:disable opening_brace
    private let unsupportedViewsPredicates: [(UIView, ViewTreeRecordingContext) -> Bool] = [
        { _, context in context.viewControllerContext.isRootView(of: .safari) },
        { _, context in context.viewControllerContext.isRootView(of: .activity) },
        { _, context in context.viewControllerContext.isRootView(of: .swiftUI) }
    ]
    // swiftlint:enable opening_brace

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard unsupportedViewsPredicates.contains(where: { $0(view, context) }) else {
            return nil
        }
        guard attributes.isVisible else {
            return InvisibleElement(subtreeStrategy: .ignore)
        }

        let builder = UnsupportedViewWireframesBuilder(
            wireframeRect: view.frame,
            wireframeID: context.ids.nodeID(view: view, nodeRecorder: self),
            unsupportedClassName: context.viewControllerContext.name ?? String(reflecting: type(of: view)),
            attributes: attributes
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UnsupportedViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect

    let wireframeID: WireframeID
    let unsupportedClassName: String
    let attributes: ViewAttributes

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createPlaceholderWireframe(
                id: wireframeID,
                frame: attributes.frame,
                clip: attributes.clip,
                label: unsupportedClassName
            )
        ]
    }
}
#endif
