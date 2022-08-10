/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CoreGraphics

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
    let root: Snapshot

    /// An individual node in the`ViewTreeSnapshot` tree structure.
    ///
    /// The `Snapshot` can describe a view by nesting snapshots for each of its child views OR it can abstract
    /// the view along with its childs by merging their information into single snapshot. This stands for the key difference
    /// between the hierarchy of native views and hierarchy of snapshots - typically there is significantly less snapshots
    /// than number of native views they describe.
    internal struct Snapshot: Equatable {
        internal struct Frame: Equatable {
            /// The x position of this snapshot, in VTS's root view coordinate space.
            let x: Int
            /// The y position of this snapshot, in VTS's root view coordinate space.
            let y: Int
            /// The width of this snapshot.
            let width: Int
            /// The height of this snapshot.
            let height: Int
        }

        /// Snapshots of subviews.
        let children: [Snapshot]

        /// The frame of this snapshot, in VTS's root view's coordinate space.
        let frame: Frame
    }
}
