/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// A counterpart of `SRSegment`. Unlike codable `SRSegment` it can be encoded to JSON data
/// with using anonymous `records: [JSONObject]` (the original `SRSegment` requires
/// typed `[SRRecords]` which isn't possible to read unambiguously from event data stored in `DatadogCore`).
///
/// Can be considered a temporary solution until we find a way to decode `[SRRecords]` unambiguously
/// through `Codable` interface.
internal struct SegmentJSON {
    /// The RUM application ID common to all records.
    let applicationID: String
    /// The RUM session ID common to all records.
    let sessionID: String
    /// The RUM view ID common to all records.
    let viewID: String
    /// The `source` of SDK in which the segment was recorded (e.g. `"ios"`).
    let source: String
    /// The timestamp of the earliest record.
    let start: Int64
    /// The timestamp of the latest record.
    let end: Int64
    /// Records to be sent in this segment.
    let records: [JSONObject]
    /// Number of records.
    let recordsCount: Int64
    /// If there is a Full Snapshot among records.
    let hasFullSnapshot: Bool

    func toJSONObject() -> JSONObject {
        return [
            segmentKey(.application): [applicationKey(.id): applicationID],
            segmentKey(.session): [sessionKey(.id): sessionID],
            segmentKey(.view): [viewKey(.id): viewID],
            segmentKey(.source): source,
            segmentKey(.start): start,
            segmentKey(.end): end,
            segmentKey(.hasFullSnapshot): hasFullSnapshot,
            segmentKey(.records): records,
            segmentKey(.recordsCount): recordsCount,
        ]
    }
}

private func segmentKey(_ codingKey: SRSegment.CodingKeys) -> String { codingKey.stringValue }
private func applicationKey(_ codingKey: SRSegment.Application.CodingKeys) -> String { codingKey.stringValue }
private func sessionKey(_ codingKey: SRSegment.Session.CodingKeys) -> String { codingKey.stringValue }
private func viewKey(_ codingKey: SRSegment.View.CodingKeys) -> String { codingKey.stringValue }
#endif
