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

    // MARK: - Creating FSR and ISR

    /// Wireframes from last FSR or ISR.
    private var lastWireframes: [SRWireframe]?

    func createFullOrIncrementalSnapshotRecord(from snapshot: ViewTreeSnapshot, with wireframes: [SRWireframe]) -> SRRecord? {
        defer { lastWireframes = wireframes }

        if let lastWireframes = lastWireframes {
            do {
                return try createIncrementalRecord(from: snapshot, newWireframes: wireframes, lastWireframes: lastWireframes)
            } catch { // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry` to report ISR errors
                // In case of any trouble, fallback to FSR which is always possible:
                return createFullSnapshotRecord(from: snapshot, wireframes: wireframes)
            }
        } else {
            return createFullSnapshotRecord(from: snapshot, wireframes: wireframes)
        }
    }

    /// Creates Full Snapshot Record - a self-contained description of a single frame of the replay.
    private func createFullSnapshotRecord(from snapshot: ViewTreeSnapshot, wireframes: [SRWireframe]) -> SRRecord {
        let record = SRFullSnapshotRecord(
            data: .init(wireframes: wireframes),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )

        return .fullSnapshotRecord(value: record)
    }

    /// Creates Incremental Snapshot Record - an incremental description of a frame of the replay.
    /// ISRs describe minimal difference between this and previous frame in the replay.
    private func createIncrementalRecord(from snapshot: ViewTreeSnapshot, newWireframes: [SRWireframe], lastWireframes: [SRWireframe]) throws -> SRRecord? {
        let diff = try computeDiff(oldArray: lastWireframes, newArray: newWireframes)

        if diff.isEmpty {
            return nil
        }

        let record = SRIncrementalSnapshotRecord(
            data: .mutationData(
                value: .init(
                    adds: diff.adds.map { addition in .init(previousId: addition.previousID, wireframe: addition.new) },
                    removes: diff.removes.map { removal in .init(id: removal.id) },
                    updates: try diff.updates.compactMap { update in
                        let newWireframe = update.to
                        let oldWireframe = update.from
                        return try newWireframe.mutations(from: oldWireframe)
                    }
                )
            ),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )

        return .incrementalSnapshotRecord(value: record)
    }

    // TODO: RUMM-2250 Bring other types of records
}
