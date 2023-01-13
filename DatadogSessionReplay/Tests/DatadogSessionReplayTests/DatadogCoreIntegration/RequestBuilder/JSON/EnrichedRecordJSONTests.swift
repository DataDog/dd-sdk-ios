/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class EnrichedRecordJSONTests: XCTestCase {
    func testWhenDecodingEnrichedRecordData_itHasTheSameInformationAvailable() throws {
        // Given
        let enrichedRecords = EnrichedRecord(
            rumContext: .mockRandom(),
            records: .mockRandom()
        )
        let data = try encode(enrichedRecords)

        // When
        let someRecords = try EnrichedRecordJSON(jsonObjectData: data)

        // Then
        XCTAssertEqual(someRecords.applicationID, enrichedRecords.applicationID)
        XCTAssertEqual(someRecords.sessionID, enrichedRecords.sessionID)
        XCTAssertEqual(someRecords.viewID, enrichedRecords.viewID)
        XCTAssertEqual(someRecords.records.count, enrichedRecords.records.count)
        XCTAssertEqual(someRecords.hasFullSnapshot, enrichedRecords.hasFullSnapshot)
        XCTAssertEqual(someRecords.earliestTimestamp, enrichedRecords.earliestTimestamp)
        XCTAssertEqual(someRecords.latestTimestamp, enrichedRecords.latestTimestamp)

        let expected = try encode(enrichedRecords.records)
        let actual = try encode(someRecords.records)
        XCTAssertEqual(expected, actual, "Serialized records data must be equal in both `EnrichedRecord` and `EnrichedRecordJSON`")
    }

    func testWhenDecodingMalformedData_itThrows() {
        // Given
        let malrofmedData1 = "[]".data(using: .utf8)!
        let malrofmedData2 = "{}".data(using: .utf8)!

        // When & Then
        XCTAssertThrowsError(try EnrichedRecordJSON(jsonObjectData: malrofmedData1)) { error in
            let description = (error as! InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to decode Dictionary<String, Any>.Type"))
        }
        XCTAssertThrowsError(try EnrichedRecordJSON(jsonObjectData: malrofmedData2)) { error in
            let description = (error as! InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to read attribute at key path"))
        }
    }

    // MARK: - Encoding helpers

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func encode(_ jsonArray: [JSONObject]) throws -> Data {
        return try JSONSerialization.data(
            withJSONObject: jsonArray,
            options: [.sortedKeys]
        )
    }
}
