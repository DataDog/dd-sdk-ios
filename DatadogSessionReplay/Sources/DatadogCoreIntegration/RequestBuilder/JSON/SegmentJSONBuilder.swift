/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct SegmentJSONBuilderError: Error, CustomStringConvertible {
    let description: String
}

internal struct SegmentJSONBuilder {
    let source: SRSegment.Source

    /// Turns records into segments.
    /// It expects all `records` to reference the same RUM view (otherwise it throws an error).
    ///
    /// - Parameter records: records to bundle within segment
    /// - Returns: serializable segment
    func createSegmentJSON(from records: [EnrichedRecordJSON]) throws -> SegmentJSON {
        guard !records.isEmpty else {
            throw SegmentJSONBuilderError(
                description: "Records array must not be empty."
            )
        }

        // Segment state:
        var current = records[0]
        var hasFullSnapshot = current.hasFullSnapshot
        var startTime = current.earliestTimestamp
        var endTime = current.latestTimestamp

        // Verify if all records share the same RUM context and record segment state:
        for index in (1..<records.count) {
            let next = records[index]

            guard rumContextEquals(in: current, and: next) else {
                throw SegmentJSONBuilderError(
                    description: "All records must reference the same RUM context."
                )
            }

            hasFullSnapshot = hasFullSnapshot || next.hasFullSnapshot
            startTime = min(startTime, next.earliestTimestamp)
            endTime = max(endTime, next.latestTimestamp)
            current = next
        }

        return createSegmentJSON(
            records: records,
            hasFullSnapshot: hasFullSnapshot,
            startTime: startTime,
            endTime: endTime
        )
    }

    private func rumContextEquals(in record1: EnrichedRecordJSON, and record2: EnrichedRecordJSON) -> Bool {
        return record1.viewID == record2.viewID
            && record1.sessionID == record2.sessionID
            && record1.applicationID == record2.applicationID
    }

    private func createSegmentJSON(
        records: [EnrichedRecordJSON],
        hasFullSnapshot: Bool,
        startTime: Int64,
        endTime: Int64
    ) -> SegmentJSON {
        let anyRecord = records[0]
        let recordsJSONArray = records.flatMap { $0.records }

        return SegmentJSON(
            applicationID: anyRecord.applicationID,
            sessionID: anyRecord.sessionID,
            viewID: anyRecord.viewID,
            source: source.rawValue,
            start: startTime,
            end: endTime,
            records: recordsJSONArray,
            recordsCount: Int64(recordsJSONArray.count),
            hasFullSnapshot: hasFullSnapshot
        )
    }
}
