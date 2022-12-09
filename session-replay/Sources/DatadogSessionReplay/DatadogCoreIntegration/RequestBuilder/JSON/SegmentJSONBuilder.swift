/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct SegmentJSONBuilder {
    let source: SRSegment.Source

    /// Groups records into segments.
    ///
    /// It scans succeeding records and groups together ones that share the same RUM context. Each group
    /// stands for a separate segment. To ensure it produces an optimal number of segments, the `records`
    /// array must be ordered in a way that the same RUM context appears in continuous ranges.
    ///
    /// - Parameter records: records to bundle within segments
    /// - Returns: array of serializable segments
    func createSegmentJSONs(from records: [EnrichedRecordJSON]) -> [SegmentJSON] {
        guard !records.isEmpty else {
            return []
        }

        var segments: [SegmentJSON?] = []
        var current = records[0]

        // Current segment state:
        var startIndex = 0
        var hasFullSnapshot = current.hasFullSnapshot
        var startTime = current.earliestTimestamp
        var endTime = current.latestTimestamp

        // Loop through the array to find continuous ranges of records that have
        // the same RUM context. For each range create a segment:
        for index in (1..<records.count) {
            let next = records[index]

            if rumContextEquals(in: current, and: next) {
                // Continue current segment:
                hasFullSnapshot = hasFullSnapshot || next.hasFullSnapshot
                startTime = min(startTime, next.earliestTimestamp)
                endTime = max(endTime, next.latestTimestamp)
            } else {
                // Close current segment:
                segments.append(
                    createSegmentJSON(
                        records: records[startIndex..<index],
                        hasFullSnapshot: hasFullSnapshot,
                        startTime: startTime,
                        endTime: endTime
                    )
                )

                // Start next segment:
                startIndex = index
                hasFullSnapshot = next.hasFullSnapshot
                startTime = next.earliestTimestamp
                endTime = next.latestTimestamp
            }

            current = next
        }

        // Close the last segment:
        segments.append(
            createSegmentJSON(
                records: records[startIndex..<records.count],
                hasFullSnapshot: hasFullSnapshot,
                startTime: startTime,
                endTime: endTime
            )
        )

        return segments.compactMap { $0 }
    }

    private func rumContextEquals(in record1: EnrichedRecordJSON, and record2: EnrichedRecordJSON) -> Bool {
        return record1.viewID == record2.viewID
            && record1.sessionID == record2.sessionID
            && record1.applicationID == record2.applicationID
    }

    private func createSegmentJSON(
        records: ArraySlice<EnrichedRecordJSON>,
        hasFullSnapshot: Bool,
        startTime: Int64,
        endTime: Int64
    ) -> SegmentJSON? {
        guard let anyRecord = records.first else {
            // Unexpected, TODO: RUMM-2410 Send error telemetry
            return nil
        }
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
