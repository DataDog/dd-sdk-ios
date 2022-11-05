/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class EnrichedRecordsTests: XCTestCase {
    func testItHasFullSnapshot() {
        // Given
        let fullSnapshotRecordType = SRFullSnapshotRecord.mockRandom().type
        let recordsWithFSR: [SRRecord] = .mockRandom() + [.fullSnapshotRecord(value: .mockRandom())]
        let recordsWithNoFSR: [SRRecord] = .mockRandom().filter { $0.type != fullSnapshotRecordType }

        // When
        let enrichedRecords1 = EnrichedRecords(
            applicationID: .mockAny(),
            sessionID: .mockAny(),
            viewID: .mockAny(),
            records: recordsWithFSR
        )
        let enrichedRecords2 = EnrichedRecords(
            applicationID: .mockAny(),
            sessionID: .mockAny(),
            viewID: .mockAny(),
            records: recordsWithNoFSR
        )

        // Then
        XCTAssertTrue(enrichedRecords1.hasFullSnapshot)
        XCTAssertFalse(enrichedRecords2.hasFullSnapshot)
    }

    func testItComputesEarliestAndLatestTimestamps() {
        // Given
        let records: [SRRecord] = .mockRandom(count: .mockRandom(min: 1, max: 100))

        // When
        let enrichedRecords = EnrichedRecords(
            applicationID: .mockAny(),
            sessionID: .mockAny(),
            viewID: .mockAny(),
            records: records
        )

        // Then
        XCTAssertEqual(enrichedRecords.earliestTimestamp, records.map({ $0.timestamp }).reduce(.max, min))
        XCTAssertEqual(enrichedRecords.latestTimestamp, records.map({ $0.timestamp }).reduce(.min, max))
    }

    // MARK: - Encoding and decoding

    private func encode(_ value: EnrichedRecords) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func encode(_ value: AnyEnrichedRecords) throws -> Data {
        return try JSONSerialization.data(
            withJSONObject: value.jsonObject,
            options: [.sortedKeys]
        )
    }

    func testGivenEncodedEnrichedRecords_whenDecodingIntoSomeEnrichedRecords_itHasTheSameDataAvailable() throws {
        // Given
        let enrichedRecords = EnrichedRecords(
            applicationID: .mockRandom(),
            sessionID: .mockRandom(),
            viewID: .mockRandom(),
            records: .mockRandom()
        )
        let data = try encode(enrichedRecords)

        // When
        let someRecords = try AnyEnrichedRecords(jsonObjectData: data)

        // Then
        XCTAssertEqual(someRecords.applicationID, enrichedRecords.applicationID)
        XCTAssertEqual(someRecords.sessionID, enrichedRecords.sessionID)
        XCTAssertEqual(someRecords.viewID, enrichedRecords.viewID)
        XCTAssertEqual(someRecords.records.count, enrichedRecords.records.count)
        XCTAssertEqual(someRecords.hasFullSnapshot, enrichedRecords.hasFullSnapshot)
        XCTAssertEqual(someRecords.earliestTimestamp, enrichedRecords.earliestTimestamp)
        XCTAssertEqual(someRecords.latestTimestamp, enrichedRecords.latestTimestamp)

        XCTAssertEqual(data, try encode(someRecords), "`EnrichedRecords` and `AnyEnrichedRecords` must serialize into the same data")
    }

    func testWhenDecodingMalformedData_thenSomeEnrichedRecordsThrows() {
        // Given
        let malrofmedData1 = "[]".data(using: .utf8)!
        let malrofmedData2 = "{}".data(using: .utf8)!

        // When & Then
        XCTAssertThrowsError(try AnyEnrichedRecords(jsonObjectData: malrofmedData1)) { error in
            let description = (error as! InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to decode Dictionary<String, Any>.Type"))
        }
        XCTAssertThrowsError(try AnyEnrichedRecords(jsonObjectData: malrofmedData2)) { error in
            let description = (error as! InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to read attribute at key path \'applicationID\'"))
        }
    }
}

// MARK: - Convenience

internal extension SRRecord {
    var type: Int64 {
        switch self {
        case .fullSnapshotRecord(let record):           return record.type
        case .incrementalSnapshotRecord(let record):    return record.type
        case .metaRecord(let record):                   return record.type
        case .focusRecord(let record):                  return record.type
        case .viewEndRecord(let record):                return record.type
        case .visualViewportRecord(let record):         return record.type
        }
    }
}
