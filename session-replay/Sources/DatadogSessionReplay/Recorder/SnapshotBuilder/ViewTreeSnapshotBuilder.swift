/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

/// Builds `ViewTreeSnapshot` for given root view.
///
/// Note: This builder is used by `Recorder` on the main thread.
internal struct ViewTreeSnapshotBuilder {
    /// The context of building current snapshot.
    struct Context {
        /// The coordinate space to convert node positions to.
        let coordinateSpace: UICoordinateSpace
    }

    /// An array of enabled node recorders.
    ///
    /// The order in this this array  should be managed consciously. For each node, the implementation loops
    /// through `nodeRecorders` and stops on the one that recorded node semantics with highes importance.
    let nodeRecorders: [NodeRecorder]

    /// Builds the `ViewTreeSnapshot` for given root view.
    ///
    /// - Parameter rootView: the root view
    /// - Returns: snapshot describing the view tree starting in `rootView`. All properties in snapshot nodes
    /// are computed relatively to the `rootView` (e.g. the `x` and `y` position of all descendant nodes  is given
    /// as its position in the root, no matter of nesting level).
    func createSnapshot(of rootView: UIView) -> ViewTreeSnapshot {
        let context = Context(coordinateSpace: rootView)
        let viewTreeSnapshot = ViewTreeSnapshot(
            date: Date(),
            root: createNode(for: rootView, in: context)
        )
        return viewTreeSnapshot
    }

    /// Takes the native view and creates its `Node` recursively.
    private func createNode(for anyView: UIView, in context: Context) -> Node {
        let viewAttributes = ViewAttributes(
            frameInRootView: anyView.convert(anyView.bounds, to: context.coordinateSpace),
            view: anyView
        )

        var semantics: NodeSemantics = UnknownElement.constant

        for nodeRecorder in nodeRecorders {
            guard let nextSemantics = nodeRecorder.semantics(of: anyView, with: viewAttributes, in: context) else {
                continue
            }

            if nextSemantics.importance > semantics.importance {
                semantics = nextSemantics

                if nextSemantics.importance == .max {
                    // We know the current semantics is best we can get, so skip querying other `nodeRecorders`:
                    break
                }
            }
        }

        return Node(
            viewAttributes: viewAttributes,
            semantics: semantics,
            children: {
                if semantics.importance != .max {
                    // Only resolve child nodes if the semantics of parent node is low (so if the
                    // sub-tree remains ambiguous):
                    return anyView.subviews.map { createNode(for: $0, in: context) }
                } else {
                    return []
                }
            }()
        )
    }
}

extension ViewTreeSnapshotBuilder {
    init() {
        self.init(
            nodeRecorders: [
                UIViewRecorder(),
                UILabelRecorder(),
            ]
        )
    }
}
