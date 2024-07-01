/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct ViewTreeRecorder {
    /// An array of enabled node recorders.
    ///
    /// The order in this this array  should be managed consciously. For each node, the implementation loops
    /// through `nodeRecorders` and stops on the one that recorded node semantics with highes importance.
    let nodeRecorders: [NodeRecorder]

    /// Creates `Nodes` for given view and its subtree hierarchy.
    func record(_ anyView: UIView, in context: ViewTreeRecordingContext) -> [Node] {
        var nodes: [Node] = []
        recordRecursively(nodes: &nodes, view: anyView, context: context)
        return nodes
    }

    // MARK: - Private

    private func recordRecursively(
        nodes: inout [Node],
        view: UIView,
        context: ViewTreeRecordingContext
    ) {
        var context = context
        if let viewController = view.next as? UIViewController {
            context.viewControllerContext.parentType = .init(viewController)
            context.viewControllerContext.isRootView = view == viewController.view
        } else {
            context.viewControllerContext.isRootView = false
        }

        let semantics = nodeSemantics(for: view, in: context)

        if !semantics.nodes.isEmpty {
            nodes.append(contentsOf: semantics.nodes)
        }

        switch semantics.subtreeStrategy {
        case .record:
            for subview in view.subviews {
                recordRecursively(nodes: &nodes, view: subview, context: context)
            }
        case .ignore:
            break
        }
    }

    private func nodeSemantics(for view: UIView, in context: ViewTreeRecordingContext) -> NodeSemantics {
        let attributes = ViewAttributes(
            frameInRootView: view.convert(view.bounds, to: context.coordinateSpace),
            view: view
        )

        var semantics: NodeSemantics = UnknownElement.constant

        for nodeRecorder in nodeRecorders {
            guard let nextSemantics = nodeRecorder.semantics(of: view, with: attributes, in: context) else {
                continue
            }

            if nextSemantics.importance >= semantics.importance {
                semantics = nextSemantics

                if nextSemantics.importance == .max {
                    // We know the current semantics is best we can get, so skip querying other `nodeRecorders`:
                    break
                }
            }
        }

        return semantics
    }
}
#endif
