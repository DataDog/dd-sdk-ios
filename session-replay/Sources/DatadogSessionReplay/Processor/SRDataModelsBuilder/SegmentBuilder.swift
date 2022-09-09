/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds SR segment to transport SR records.
/// Segment stands for a portion of session replay (from one moment in time to another). The full session replay is
/// typically build from many segments.
///
/// Note: `SegmentBuilder` is used by `Processor` on a single background thread.
internal class SegmentBuilder {
    func createSegment(with records: [SRRecord]) throws -> SRSegment {
        guard let firstRecord = records.first, let lastRecord = records.last else {
            throw InternalError(description: "Segment cannot contain no records")
        }
        guard case SRRecord.metaRecord(let metaRecord) = firstRecord else {
            throw InternalError(description: "The first record in a Segment must be Meta Record")
        }
        guard case SRRecord.mobileFullSnapshotRecord(let lastFullSnapshotRecord) = lastRecord else {
            // TODO: RUMM-2250 Make it more generic after introducing more record types
            throw InternalError(description: "For now, Segment must end with Full Snapshot Record")
        }

        return SRSegment(
            application: .init(id: ""),
            end: lastFullSnapshotRecord.timestamp,
            hasFullSnapshot: true,
            indexInView: 0,
            records: records,
            recordsCount: Int64(records.count),
            session: .init(id: ""),
            source: .ios,
            start: metaRecord.timestamp,
            view: .init(id: "")
        )
    }
}
