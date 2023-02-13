/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class SegmentJSONBuilderTests: XCTestCase {
    private let builder = SegmentJSONBuilder(source: .mockRandom())

    func testGivenSRSegmentWithRecords_whenCreatingSegmentJSON_itEcodesToTheSameJSON() throws {
        // Given
        let expectedSegment = generateSegment(maxRecordsCount: 50)
        let records = try generateEnrichedRecordJSONs(for: expectedSegment)

        // When
        let actualSegment = try builder.createSegmentJSON(from: records)

        // Then
        XCTAssertEqual(
            try prettyJSONString(for: expectedSegment),
            try prettyJSONString(for: actualSegment),
            "`SegmentJSON` must encode the same JSON string as `SRSegment: Codable`"
        )
    }

    func testWhenBuildingSegmentWithNoRecords_itThrows() {
        // When
        XCTAssertThrowsError(try builder.createSegmentJSON(from: [])) { error in
            // Then
            XCTAssertEqual((error as? SegmentJSONBuilderError)?.description, "Records array must not be empty.")
        }
    }

    func testWhenBuildingSegmentWithInvalidRecords_itThrows() throws {
        // Given
        let segment1 = generateSegment(maxRecordsCount: 25)
        let segment2 = generateSegment(maxRecordsCount: 25)
        let records = try generateEnrichedRecordJSONs(for: segment1) + generateEnrichedRecordJSONs(for: segment2)

        // When
        XCTAssertThrowsError(try builder.createSegmentJSON(from: records)) { error in
            // Then
            XCTAssertEqual((error as? SegmentJSONBuilderError)?.description, "All records must reference the same RUM context.")
        }
    }

    // MARK: - Fuzzy Helpers

    private func generateSegment(maxRecordsCount: Int64 = 100) -> SRSegment {
        let recordsCount: Int64 = .mockRandom(min: 1, max: maxRecordsCount)
        let records: [SRRecord] = (0..<recordsCount).map { _ in .mockRandom() }
        let timestamps = records.map { $0.timestamp }

        return SRSegment(
            application: .init(id: .mockRandom()),
            end: timestamps.min(by: >)!,
            hasFullSnapshot: records.contains { $0.isFullSnapshot },
            indexInView: nil,
            records: records,
            recordsCount: recordsCount,
            session: .init(id: .mockRandom()),
            source: builder.source,
            start: timestamps.min(by: <)!,
            view: .init(id: .mockRandom())
        )
    }

    private func generateEnrichedRecordJSONs(for segment: SRSegment) throws -> [EnrichedRecordJSON] {
        let rum = RUMContext(
            ids: .init(
                applicationID: segment.application.id,
                sessionID: segment.session.id,
                viewID: segment.view.id
            ),
            viewServerTimeOffset: 0
        )
        return try segment.records
            // To make it more challenging for tested `SegmentJSONBuilder`, we chunk records in
            // expected `segment`, so they are spread among many enriched records:
            .chunkedRandomly(numberOfChunks: .random(in: 1...segment.records.count))
            .map { EnrichedRecord(rumContext: rum, records: $0) }
            // Encode `EnrichedRecords` into `Data`, just like it happens in `DatadogCore` when
            // writting them into batches:
            .map { try encode($0) }
            // Decode it back to `EnrichedRecordJSON` just like it happens when preparing
            // upload requests for SR:
            .map { try EnrichedRecordJSON(jsonObjectData: $0) }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(value)
    }

    private func encode(_ segment: SegmentJSON) throws -> Data {
        return try JSONSerialization.data(
            withJSONObject: segment.toJSONObject(),
            options: [.sortedKeys, .prettyPrinted]
        )
    }

    private func prettyJSONString<T: Encodable>(for value: T) throws -> String {
        return String(data: try encode(value), encoding: .utf8) ?? ""
    }

    private func prettyJSONString(for segment: SegmentJSON) throws -> String {
        return String(data: try encode(segment), encoding: .utf8) ?? ""
    }
}
