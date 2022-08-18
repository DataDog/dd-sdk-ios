/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// TODO: RUMM-2440 - configure models generator to emit root-level `SRWireframe` instead of this
internal typealias SRWireframe = SRMobileFullSnapshotRecord.Data.Wireframes

/// Builds the actual wireframes from VTS snapshots (produced by `Recorder`) to be later transported in SR
/// records (see `RecordsBuilder`) within SR segments (see `SegmentBuilder`).
/// A wireframe stands for semantic definition of an UI element (i.a.: label, button, tab bar).
/// It is used by the player to reconstruct individual elements of the recorded app UI.
///
/// Note: `WireframesBuilder` is used by `Processor` on a single background thread.
internal class WireframesBuilder {
    /// TODO: RUMM-2272 Add a stable way of managing wireframe IDs (so they can be reduced in incremental SR records)
    var dummyIDsGenerator: Int64 = 0

    func createShapeWireframe(from node: Node) -> SRWireframe {
        dummyIDsGenerator += 1

        // TODO: RUMM-2429 Record real appearance information in `Node`
        let shape = SRShapeWireframe(
            border: .init(color: "#4900FF", width: 1),
            height: node.frame.height,
            id: dummyIDsGenerator,
            shapeStyle: nil,
            width: node.frame.width,
            x: node.frame.x,
            y: node.frame.y
        )

        return .shapeWireframe(value: shape)
    }

    // TODO: RUMM-2429 Create specialised wireframes for different UI elements
}
