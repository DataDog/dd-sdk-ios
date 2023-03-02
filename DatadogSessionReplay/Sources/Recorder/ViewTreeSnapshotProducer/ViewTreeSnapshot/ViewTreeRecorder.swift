/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// The context of recording subtree hierarchy.
///
/// Some fields are mutable, so `NodeRecorders` can specialise it for their subtree traversal.
internal struct ViewTreeRecordingContext {
    /// The context of the Recorder.
    let recorder: Recorder.Context
    /// The coordinate space to convert node positions to.
    let coordinateSpace: UICoordinateSpace
    /// Generates stable IDs for traversed views.
    let ids: NodeIDGenerator
    /// Masks text in recorded nodes.
    /// Can be overwriten in by `NodeRecorder` if their subtree recording requires different masking.
    var textObfuscator: TextObfuscating
    /// Allows `NodeRecorders` to modify semantics of nodes in their subtree.
    /// It gets called each time when a new semantic is found.
    ///
    /// The closure takes: current semantics, the `UIView` object and its `ViewAttributes`.
    /// The closure implementation should return new semantics for that element.
    var semanticsOverride: ((NodeSemantics, UIView, ViewAttributes) -> NodeSemantics)? = nil
}

internal struct ViewTreeRecorder {
    /// An array of enabled node recorders.
    ///
    /// The order in this this array  should be managed consciously. For each node, the implementation loops
    /// through `nodeRecorders` and stops on the one that recorded node semantics with highes importance.
    let nodeRecorders: [NodeRecorder]

    /// Creates `Nodes` for given view and its subtree hierarchy.
    func recordNodes(for anyView: UIView, in context: ViewTreeRecordingContext) -> [Node] {
        var nodes: [Node] = []
        recordRecursively(nodes: &nodes, view: anyView, context: context)
        return nodes
    }

    // MARK: - Private

    private func recordRecursively(nodes: inout [Node], view: UIView, context: ViewTreeRecordingContext) {
        let node = node(for: view, in: context)
        nodes.append(node)

        switch node.semantics.subtreeStrategy {
        case .record:
            for subview in view.subviews {
                recordRecursively(nodes: &nodes, view: subview, context: context)
            }
        case .replace(let subtreeNodes):
            nodes.append(contentsOf: subtreeNodes)
        case .ignore:
            break
        }
    }

    private func node(for view: UIView, in context: ViewTreeRecordingContext) -> Node {
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

                if let semanticsOverride = context.semanticsOverride {
                    semantics = semanticsOverride(semantics, view, attributes)
                }

                if nextSemantics.importance == .max {
                    // We know the current semantics is best we can get, so skip querying other `nodeRecorders`:
                    break
                }
            }
        }

        return Node(viewAttributes: attributes, semantics: semantics)
    }
}
