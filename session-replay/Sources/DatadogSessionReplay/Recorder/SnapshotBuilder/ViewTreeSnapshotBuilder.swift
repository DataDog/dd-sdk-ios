/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

internal typealias Node = ViewTreeSnapshot.Node

/// Builds `ViewTreeSnapshot` for given root view.
///
/// Note: This builder is used by `Recorder` on the main thread.
internal struct ViewTreeSnapshotBuilder {
    /// The context of building current snapshot.
    private struct Context {
        let rootView: UIView
    }

    /// Builds the `ViewTreeSnapshot` for given root view.
    ///
    /// - Parameter rootView: the root view
    /// - Returns: snapshot describing the view tree starting in `rootView`. All properties in snapshot nodes
    /// are computed relatively to the `rootView` (e.g. the `x` and `y` position of all descendant nodes  is given
    /// as its position in the root, no matter of nesting level).
    func createSnapshot(of rootView: UIView) throws -> ViewTreeSnapshot {
        let context = Context(rootView: rootView)
        let viewTreeSnapshot = ViewTreeSnapshot(
            date: Date(),
            root: createNode(for: rootView, in: context)
        )
        return viewTreeSnapshot
    }

    private func createNode(for anyView: UIView, in context: Context) -> Node {
        let frameInRoot = anyView.convert(anyView.bounds, to: context.rootView)
        let node = Node(
            children: anyView.subviews.map { createNode(for: $0, in: context) },
            frame: Node.Frame(cgRect: frameInRoot)
        )
        return node
    }

    // TODO: RUMM-2429 Collect semantic information on various UI elements (UIButton, UILabel, UITabBar, ...)
}

// MARK: - Convenience

extension Node.Frame {
    init(cgRect: CGRect) {
        self.init(
            x: Int64(withNoOverflow: cgRect.origin.x),
            y: Int64(withNoOverflow: cgRect.origin.y),
            width: Int64(withNoOverflow: cgRect.size.width),
            height: Int64(withNoOverflow: cgRect.size.height)
        )
    }
}
