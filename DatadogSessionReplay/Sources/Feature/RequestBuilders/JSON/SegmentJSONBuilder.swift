/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

internal struct SegmentJSONBuilderError: Error, CustomStringConvertible {
    let description: String
}

internal struct SegmentJSONBuilder {
    let source: SRSegment.Source

    func segments(from records: [EnrichedRecordJSON]) throws -> [SegmentJSON] {
        guard !records.isEmpty else {
            throw SegmentJSONBuilderError(description: "Records array must not be empty.")
        }

        var indexes: [String: Int] = [:]
        return records.reduce(into: []) { segments, record in
            if let index = indexes[record.viewID] {
                let segment = segments[index]
                segments[index] = SegmentJSON(
                    applicationID: segment.applicationID,
                    sessionID: segment.sessionID,
                    viewID: segment.viewID,
                    source: segment.source,
                    start: min(segment.start, record.earliestTimestamp),
                    end: max(segment.end, record.latestTimestamp),
                    records: segment.records + record.records,
                    recordsCount: segment.recordsCount + Int64(record.records.count),
                    hasFullSnapshot: segment.hasFullSnapshot || record.hasFullSnapshot
                )
            } else {
                indexes[record.viewID] = segments.count
                segments.append(SegmentJSON(
                    applicationID: record.applicationID,
                    sessionID: record.sessionID,
                    viewID: record.viewID,
                    source: source.rawValue,
                    start: record.earliestTimestamp,
                    end: record.latestTimestamp,
                    records: record.records,
                    recordsCount: Int64(record.records.count),
                    hasFullSnapshot: record.hasFullSnapshot
                ))
            }
        }
    }
}
#endif
