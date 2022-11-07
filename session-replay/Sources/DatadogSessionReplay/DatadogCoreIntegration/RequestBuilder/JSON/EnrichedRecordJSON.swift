/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias JSONObject = [String: Any]

/// A partial type erasure for `EnrichedRecord` - it provides the same information as `EnrichedRecord`
/// but can be both encoded and decoded.
///
/// `EnrichedRecordJSON` is decoded from `DatadogCore` storage right before preparing SR upload. It is
/// later encoded into `URLRequest` passed back to the core.
///
/// It provides type-safe access to meta information required for building SR payloads. Data that needs to be encoded
/// into request body is available on `jsonObject: [String: Any]` and can be serialized with `JSONSerialization`.
internal struct EnrichedRecordJSON {
    /// Records enriched with further information.
    let records: [JSONObject]

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

    init(jsonObjectData: Data) throws {
        let jsonObject: JSONObject = try decode(jsonObjectData)

        self.records = try read(codingKey: .records, from: jsonObject)
        self.applicationID = try read(codingKey: .applicationID, from: jsonObject)
        self.sessionID = try read(codingKey: .sessionID, from: jsonObject)
        self.viewID = try read(codingKey: .viewID, from: jsonObject)
        self.hasFullSnapshot = try read(codingKey: .hasFullSnapshot, from: jsonObject)
        self.earliestTimestamp = try read(codingKey: .earliestTimestamp, from: jsonObject)
        self.latestTimestamp = try read(codingKey: .latestTimestamp, from: jsonObject)
    }
}

private func decode<T>(_ data: Data) throws -> T {
    guard let value = try JSONSerialization.jsonObject(with: data) as? T else {
        throw InternalError(description: "Failed to decode \(type(of: T.self))")
    }
    return value
}

private func read<T>(codingKey: EnrichedRecord.CodingKeys, from object: JSONObject) throws -> T {
    guard let value = object[codingKey.stringValue] as? T else {
        throw InternalError(description: "Failed to read attribute at key path '\(codingKey.stringValue)'")
    }
    return value
}
