/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class SegmentJSONBuilderTests: XCTestCase {
    private let builder = SegmentJSONBuilder(source: .mockRandom())

    func testGivenSRSegmentWithRecords_whenCreatingSegmentJSON_itEcodesToTheSameJSON() throws {
        // Given
        let expectedSegment = generateSegment(maxRecordsCount: 1)
        let records = try generateEnrichedRecordJSONs(for: expectedSegment)

        // When
        let actualSegments = builder.createSegmentJSONs(from: records)

        // Then
        XCTAssertEqual(actualSegments.count, 1)
        XCTAssertEqual(
            try prettyJSONString(for: expectedSegment),
            try prettyJSONString(for: actualSegments[0]),
            "`SegmentJSON` must encode the same JSON string as `SRSegment: Codable`"
        )
    }

    func testGivenMultipleSRSegmentsWithRecords_whenCreatingSegmentJSONs_theyEcodeToTheSameJSON() throws {
        let expectedSegments = (0..<50).map { generateSegment(maxRecordsCount: $0 + 1) }

        // Given
        let records = try expectedSegments.flatMap { try generateEnrichedRecordJSONs(for: $0) }

        // When
        let actualSegments = builder.createSegmentJSONs(from: records)

        // Then
        XCTAssertEqual(actualSegments.count, expectedSegments.count)
        try zip(actualSegments, expectedSegments).forEach { actual, expected in
            XCTAssertEqual(
                try prettyJSONString(for: expected),
                try prettyJSONString(for: actual),
                "`SegmentJSON` must encode the same JSON string as `SRSegment: Codable`"
            )
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
            applicationID: segment.application.id,
            sessionID: segment.session.id,
            viewID: segment.view.id
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
