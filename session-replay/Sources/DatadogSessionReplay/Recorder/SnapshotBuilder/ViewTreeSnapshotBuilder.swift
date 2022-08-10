/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

private typealias Snapshot = ViewTreeSnapshot.Snapshot

/// Builds `ViewTreeSnapshot` for given root view.
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
            root: createSnapshot(of: rootView, in: context)
        )
        return viewTreeSnapshot
    }

    private func createSnapshot(of anyView: UIView, in context: Context) -> Snapshot {
        let frameInRoot = anyView.convert(anyView.bounds, to: context.rootView)
        let snapshot = Snapshot(
            children: anyView.subviews.map { createSnapshot(of: $0, in: context) },
            frame: Snapshot.Frame(cgRect: frameInRoot)
        )
        return snapshot
    }
}

// MARK: - Convenience

extension Snapshot.Frame {
    init(cgRect: CGRect) {
        self.init(
            x: Int(withNoOverflow: cgRect.origin.x),
            y: Int(withNoOverflow: cgRect.origin.y),
            width: Int(withNoOverflow: cgRect.size.width),
            height: Int(withNoOverflow: cgRect.size.height)
        )
    }
}
