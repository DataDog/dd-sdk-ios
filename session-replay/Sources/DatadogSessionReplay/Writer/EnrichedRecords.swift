/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Bundles SR records with their RUM context and other information required for preparing SR upload.
///
/// `EnrichedRecords` are produced by `Processor` and written to `DatadogCore` storage.
/// By saving records soon after they are created we ensure that replay data can be consistently uploaded
/// even if the session was suddenly terminated by a crash.
///
/// `EnrichedRecords` conforms to `Encodable` meaning that it can be encoded by `DatadogCore`,
/// but not decoded back. For decoding `EnrichedRecords`, see `AnyEnrichedRecords` type.
internal struct EnrichedRecords: Encodable {
    /// RUM applicaiton ID.
    let applicationID: String
    /// RUM session ID.
    let sessionID: String
    /// RUM view ID.
    let viewID: String
    /// Records recorded in this RUM context.
    let records: [SRRecord]

    /// If `records` array includes a Full Snapshot record.
    let hasFullSnapshot: Bool
    /// The timestamp of the earliest record.
    let earliestTimestamp: Int64
    /// The timestamp of the latest record.
    let latestTimestamp: Int64

    enum CodingKeys: String, CodingKey {
        case applicationID
        case sessionID
        case viewID
        case records
        case hasFullSnapshot
        case earliestTimestamp
        case latestTimestamp
    }

    init(applicationID: String, sessionID: String, viewID: String, records: [SRRecord]) {
        self.applicationID = applicationID
        self.sessionID = sessionID
        self.viewID = viewID
        self.records = records

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

internal typealias JSONObject = [String: Any]

/// A partial type erasure for `EnrichedRecords` - it provides the same information as `EnrichedRecords`
/// but can be both encoded and decoded.
///
/// `AnyEnrichedRecords` is decoded from `DatadogCore` storage right before preparing SR upload. It is
/// later encoded into `URLRequest` passed back to the core.
///
/// It provides type-safe access to meta information required for building SR payloads. Data that needs to be encoded
/// into request body is available on `jsonObject: [String: Any]` and can be serialized with `JSONSerialization`.
internal struct AnyEnrichedRecords {
    typealias CodingKeys = EnrichedRecords.CodingKeys

    /// RUM applicaiton ID.
    let applicationID: String
    /// RUM session ID.
    let sessionID: String
    /// RUM view ID.
    let viewID: String
    /// Records recorded in this RUM context.
    let records: [JSONObject]

    /// If `records` array includes a Full Snapshot record.
    let hasFullSnapshot: Bool
    /// The timestamp of the earliest record.
    let earliestTimestamp: Int64
    /// The timestamp of the latest record.
    let latestTimestamp: Int64

    /// An ambiguous JSON object that encodes the whole `EnrichedRecords` information.
    /// When encoded with `JSONSerialization` it will result with original data of `EnrichedRecords`.
    let jsonObject: JSONObject

    init(jsonObjectData: Data) throws {
        self.jsonObject = try decode(jsonObjectData)
        self.applicationID = try read(codingKey: CodingKeys.applicationID, from: jsonObject)
        self.sessionID = try read(codingKey: CodingKeys.sessionID, from: jsonObject)
        self.viewID = try read(codingKey: CodingKeys.viewID, from: jsonObject)
        self.records = try read(codingKey: CodingKeys.records, from: jsonObject)
        self.hasFullSnapshot = try read(codingKey: CodingKeys.hasFullSnapshot, from: jsonObject)
        self.earliestTimestamp = try read(codingKey: CodingKeys.earliestTimestamp, from: jsonObject)
        self.latestTimestamp = try read(codingKey: CodingKeys.latestTimestamp, from: jsonObject)
    }
}

private func decode<T>(_ data: Data) throws -> T {
    guard let value = try JSONSerialization.jsonObject(with: data) as? T else {
        throw InternalError(description: "Failed to decode \(type(of: T.self))")
    }
    return value
}

private func read<T>(codingKey: CodingKey, from object: JSONObject) throws -> T {
    guard let value = object[codingKey.stringValue] as? T else {
        throw InternalError(description: "Failed to read attribute at key path '\(codingKey.stringValue)'")
    }
    return value
}

// MARK: - Convenience

internal extension SRRecord {
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
