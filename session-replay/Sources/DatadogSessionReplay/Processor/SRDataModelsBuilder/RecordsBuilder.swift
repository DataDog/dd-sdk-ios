/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds SR records from VTS snapshots to transport wireframes (see `WireframesBuilder`).
/// There are several types of records in SR format, including Full Snapshot Record (FSR contains all wireframes
/// of a single replay frame), Incremental Snapshot Record (ISR describes only changes since prior ISR and FSR)
/// and several meta records (for providing other information to the player).
///
/// Note: `RecordsBuilder` is used by `Processor` on a single background thread.
internal class RecordsBuilder {
    /// Creates Meta Record, defining the viewport size of the player.
    func createMetaRecord(from snapshot: ViewTreeSnapshot) -> SRRecord {
        let record = SRMetaRecord(
            data: .init(
                height: Int64(withNoOverflow: snapshot.root.viewAttributes.frame.height),
                href: nil,
                width: Int64(withNoOverflow: snapshot.root.viewAttributes.frame.width)
            ),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )
        return .metaRecord(value: record)
    }

    /// Creates Focus Record - 🚧 it's required by the contract with the player, but doesn't bring anything for mobile.
    /// TODO: RUMM-2250 remove if we decide to not go with FRs.
    func createFocusRecord(from snapshot: ViewTreeSnapshot) -> SRRecord {
        let record = SRFocusRecord(
            data: SRFocusRecord.Data(hasFocus: true),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )
        return .focusRecord(value: record)
    }

    /// Creates Full Snapshot Record - bringing self-contained description of a single frame of the replay.
    func createFullSnapshotRecord(from snapshot: ViewTreeSnapshot, with wireframes: [SRWireframe]) -> SRRecord {
        let record = SRFullSnapshotRecord(
            data: .init(wireframes: wireframes),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )
        return .fullSnapshotRecord(value: record)
    }

    // TODO: RUMM-2250 Bring other types of records
}
