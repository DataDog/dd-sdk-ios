/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Bundles SR records with their RUM context and other information required for preparing SR upload.
///
/// `EnrichedRecord` are produced by `Processor` and written to `DatadogCore` storage.
/// By saving records soon after they are created we ensure that replay data can be consistently uploaded
/// even if the session was suddenly terminated by a crash.
///
/// `EnrichedRecord` conforms to `Encodable` so it can be encoded by `DatadogCore`.
/// For decoding `EnrichedRecord` information, see `EnrichedRecordJSON` type.
internal struct EnrichedRecord: Encodable {
    /// Records enriched with further information.
    let records: [SRRecord]

    /// The RUM application ID of all records.
    let applicationID: String
    /// The RUM session ID of all records.
    let sessionID: String
    /// The RUM view ID of all records.
    let viewID: String
    /// If there is a Full Snapshot among records.
    let hasFullSnapshot: Bool
    /// The timestamp of the earliest record.
    let earliestTimestamp: Int64
    /// The timestamp of the latest record.
    let latestTimestamp: Int64

    enum CodingKeys: String, CodingKey {
        case records
        case applicationID
        case sessionID
        case viewID
        case hasFullSnapshot
        case earliestTimestamp
        case latestTimestamp
    }

    init(rumContext: RUMContext, records: [SRRecord]) {
        self.records = records
        self.applicationID = rumContext.ids.applicationID
        self.sessionID = rumContext.ids.sessionID
        self.viewID = rumContext.ids.viewID

        var hasFullSnapshot = false
        var earliestTimestamp: Int64 = .max
        var latestTimestamp: Int64 = .min

        for record in records {
            hasFullSnapshot = hasFullSnapshot || record.isFullSnapshot
            earliestTimestamp = min(record.timestamp, earliestTimestamp)
            latestTimestamp = max(record.timestamp, latestTimestamp)
        }

        self.hasFullSnapshot = hasFullSnapshot
        self.earliestTimestamp = earliestTimestamp
        self.latestTimestamp = latestTimestamp
    }
}

// MARK: - Convenience

extension SRRecord {
    var isFullSnapshot: Bool {
        switch self {
        case .fullSnapshotRecord: return true
        default: return false
        }
    }

    var timestamp: Int64 {
        switch self {
        case .fullSnapshotRecord(let record):           return record.timestamp
        case .incrementalSnapshotRecord(let record):    return record.timestamp
        case .metaRecord(let record):                   return record.timestamp
        case .focusRecord(let record):                  return record.timestamp
        case .viewEndRecord(let record):                return record.timestamp
        case .visualViewportRecord(let record):         return record.timestamp
        }
    }
}
