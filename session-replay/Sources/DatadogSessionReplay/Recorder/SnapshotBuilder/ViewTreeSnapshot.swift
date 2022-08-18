/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `ViewTreeSnapshot` is an intermediate representation of the app UI in Session Replay
/// recording: [views hierarchy] → [`ViewTreeSnapshot`] → [wireframes].
///
/// Although it's being built from the actual views hierarchy, it doesn't correspond 1:1 to it. Similarly,
/// it doesn't translate 1:1 into wireframes that get uploaded to the SR BE. Instead, it provides its
/// own description of the view hierarchy, which can be optimised for efficiency in SR recorder (e.g. unlike
/// the real views hierarchy, `ViewTreeSnapshot` is meant to be safe when accesed on a background thread).
internal struct ViewTreeSnapshot: Equatable {
    /// The time of taking this snapshot.
    let date: Date

    /// The snapshot of a root view.
    let root: Node

    /// An individual node in the`ViewTreeSnapshot` tree structure. It denotes a snapshot of an individual view
    /// or views hierarchy.
    ///
    /// The `Node` can describe a view by nesting nodes for each of its child views OR it can abstract
    /// the view along with its childs by merging their information into single node. This stands for the key difference
    /// between the hierarchy of native views and hierarchy of nodes - typically there is significantly less nodes
    /// than number of native views they describe.
    internal struct Node: Equatable {
        internal struct Frame: Equatable {
            /// The x position of this node, in VTS's root view coordinate space.
            let x: Int64
            /// The y position of this node, in VTS's root view coordinate space.
            let y: Int64
            /// The width of this node.
            let width: Int64
            /// The height of this node.
            let height: Int64
        }

        /// Nodes (snapshots) denoting subviews of this node's view.
        let children: [Node]

        /// The frame of this node, in VTS's root view's coordinate space.
        let frame: Frame
    }
}
