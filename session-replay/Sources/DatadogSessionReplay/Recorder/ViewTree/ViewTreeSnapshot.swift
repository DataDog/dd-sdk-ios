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
internal struct ViewTreeSnapshot {
    /// The time of taking this snapshot.
    let date: Date

    // TODO: RUMM-2411 Define view tree snapshot
}
