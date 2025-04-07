/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Matcher for asserting known values of Session Replay Segment.
///
/// See: ``DatadogSessionReplay.SRSegment`` to understand how underlying data is encoded.
internal class SRSegmentMatcher: JSONObjectMatcher {
    /// Enumerates SR record types.
    /// Raw values correspond to record types defined in SR JSON schema.
    ///
    /// See: ``DatadogSessionReplay.SRRecord``
    enum RecordType: Int {
        case fullSnapshotRecord = 10
        case incrementalSnapshotRecord = 11
        case metaRecord = 4
        case focusRecord = 6
        case viewEndRecord = 7
        case visualViewportRecord = 8
    }

    /// The value of "segment" field in underlying multipart form.
    func segment() throws -> String { try value("segment") }

    /// The value of "application.id" field in underlying multipart form.
    func applicationID() throws -> String { try value("application.id") }

    /// The value of "session.id" field in underlying multipart form.
    func sessionID() throws -> String { try value("session.id") }

    /// The  value of "view.id" field in underlying multipart form.
    func viewID() throws -> String { try value("view.id") }

    /// The  value of "has_full_snapshot" field in underlying multipart form.
    func hasFullSnapshot() throws -> Bool { try value("has_full_snapshot") }

    /// The  value of "records_count" field in underlying multipart form.
    func recordsCount() throws -> Int { try value("records_count") }

    /// The  value of "raw_segment_size" field in underlying multipart form.
    func rawSegmentSize() throws -> Int { try value("raw_segment_size") }

    /// The  value of "compressed_segment_size" field in underlying multipart form.
    func compressedSegmentSize() throws -> Int { try value("compressed_segment_size") }

    /// The  value of "start" field in underlying multipart form.
    func start() throws -> Int { try value("start") }

    /// The  value of "end" field in underlying multipart form.
    func end() throws -> Int { try value("end") }

    /// The  value of "source" field in underlying multipart form.
    func source() throws -> String { try value("source") }

    /// Returns an array of JSON object matchers for all records in this segment.
    func records() throws -> [JSONObjectMatcher] {
        try array("records").objects()
    }

    /// Returns an array of JSON object matchers for records of a specific type.
    /// - Parameter type: The type of records to retrieve.
    /// - Returns: An array of `JSONObjectMatcher` instances representing the records of the specified type.
    func records(type: RecordType) throws -> [JSONObjectMatcher] {
        try records().filter { try $0.value("type") == type.rawValue }
    }

    /// Returns an array of specialised matchers for "full snapshot" records.
    func fullSnapshotRecords() throws -> [SRFullSnapshotRecordMatcher] {
        try records(type: .fullSnapshotRecord).map { SRFullSnapshotRecordMatcher(jsonObject: $0.object) }
    }

    /// Returns an array of specialised matchers for "incremental snapshot" records.
    func incrementalSnapshotRecords() throws -> [SRIncrementalSnapshotRecordMatcher] {
        try records(type: .incrementalSnapshotRecord).map { SRIncrementalSnapshotRecordMatcher(jsonObject: $0.object) }
    }
}

/// Matcher for asserting known values of Session Replay "full snapshot" record.
///
/// See: ``DatadogSessionReplay.SRFullSnapshotRecord`` to understand how underlying data is encoded.
internal class SRFullSnapshotRecordMatcher: JSONObjectMatcher {
    init(jsonObject: [String: Any]) {
        super.init(object: jsonObject)
    }

    /// Returns an array of JSON object matchers for wireframes contained in this record.
    func wireframes() throws -> [JSONObjectMatcher] {
        try array("data.wireframes").objects()
    }
}

/// Matcher for asserting known values of Session Replay "incremental snapshot" record.
///
/// See: ``DatadogSessionReplay.SRIncrementalSnapshotRecord`` to understand how underlying data is encoded.
internal class SRIncrementalSnapshotRecordMatcher: JSONObjectMatcher {
    init(jsonObject: [String: Any]) {
        super.init(object: jsonObject)
    }

    /// Enumerates data types in incremental snapshot.
    /// Raw values correspond to types defined in SR JSON schema.
    ///
    /// See: ``DatadogSessionReplay.SRIncrementalSnapshotRecord.Data``
    enum IncrementalDataType: Int {
        case mutationData = 0
        case touchData = 2
        case viewportResizeData = 4
        case pointerInteractionData = 9
    }

    func has(incrementalDataType: IncrementalDataType) throws -> Bool {
        return try value("data.source") == incrementalDataType.rawValue
    }
}
