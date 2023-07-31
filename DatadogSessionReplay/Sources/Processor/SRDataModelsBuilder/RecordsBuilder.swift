/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builds SR records from VTS snapshots to transport wireframes (see `WireframesBuilder`).
/// There are several types of records in SR format, including Full Snapshot Record (FSR contains all wireframes
/// of a single replay frame), Incremental Snapshot Record (ISR describes only changes since prior ISR and FSR)
/// and several meta records (for providing other information to the player).
///
/// Note: `RecordsBuilder` is used by `Processor` on a single background thread.
internal class RecordsBuilder {
    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry

    init(telemetry: Telemetry) {
        self.telemetry = telemetry
    }

    /// Creates Meta Record, defining the viewport size of the player.
    func createMetaRecord(from snapshot: ViewTreeSnapshot) -> SRRecord {
        let record = SRMetaRecord(
            data: .init(
                height: Int64(withNoOverflow: snapshot.viewportSize.height),
                href: nil,
                width: Int64(withNoOverflow: snapshot.viewportSize.width)
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

    /// Creates Full Snapshot Record - a self-contained description of a single frame of the replay.
    func createFullSnapshotRecord(from snapshot: ViewTreeSnapshot, wireframes: [SRWireframe]) -> SRRecord {
        let record = SRFullSnapshotRecord(
            data: .init(wireframes: wireframes),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )

        return .fullSnapshotRecord(value: record)
    }

    /// Creates Incremental Snapshot Record - an incremental description of a frame of the replay.
    /// ISRs describe minimal difference between this and previous frame in the replay.
    ///
    /// It may return `nil` if there is no diff between `wireframes` and `lastWireframes`.
    /// In case of unexpected failure, it will fallback to creating FSR instead.
    func createIncrementalSnapshotRecord(from snapshot: ViewTreeSnapshot, with wireframes: [SRWireframe], lastWireframes: [SRWireframe]) -> SRRecord? {
        do {
            return try createIncrementalSnapshotRecord(from: snapshot, newWireframes: wireframes, lastWireframes: lastWireframes)
        } catch {
            // In case of any trouble, fallback to FSR which is always possible:
            telemetry.error("[SR] Failed to create incremental record", error: DDError(error: error))
            return createFullSnapshotRecord(from: snapshot, wireframes: wireframes)
        }
    }

    private func createIncrementalSnapshotRecord(from snapshot: ViewTreeSnapshot, newWireframes: [SRWireframe], lastWireframes: [SRWireframe]) throws -> SRRecord? {
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
                        return try update.to.mutations(from: update.from)
                    }
                )
            ),
            timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
        )

        return .incrementalSnapshotRecord(value: record)
    }

    func createIncrementalSnapshotRecords(from snapshot: TouchSnapshot) -> [SRRecord] {
        return snapshot.touches.map { touch in
            let record = SRIncrementalSnapshotRecord(
                data: .pointerInteractionData(
                    value: .init(
                        pointerEventType: {
                            switch touch.phase {
                            case .down: return .down
                            case .move: return .move
                            case .up: return .up
                            }
                        }(),
                        pointerId: touch.id,
                        pointerType: .touch,
                        x: round(touch.position.x),
                        y: round(touch.position.y)
                    )
                ),
                timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
            )
            return .incrementalSnapshotRecord(value: record)
        }
    }

    func createViewport(
        from snapshot: ViewTreeSnapshot,
        lastSnapshot: ViewTreeSnapshot
    ) -> SRRecord? {
        guard lastSnapshot.viewportSize.aspectRatio != snapshot.viewportSize.aspectRatio else {
            return nil
        }
        return .incrementalSnapshotRecord(
            value: SRIncrementalSnapshotRecord(
                data: .viewportResizeData(
                    value: .init(
                        height: Int64(withNoOverflow: snapshot.viewportSize.height),
                        width: Int64(withNoOverflow: snapshot.viewportSize.width)
                    )
                ),
                timestamp: snapshot.date.timeIntervalSince1970.toInt64Milliseconds
            )
        )
    }

    // TODO: RUMM-2250 Bring other types of records
}
