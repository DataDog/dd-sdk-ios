/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogSessionReplay

class SegmentJSONBuilderTests: XCTestCase {
    private let builder = SegmentJSONBuilder(source: .mockRandom())

    func testGivenSRSegmentWithRecords_whenCreatingSegmentJSON_itEcodesToTheSameJSON() throws {
        // Given
        let segment1 = generateSegment(maxRecordsCount: 50)
        let segment2 = generateSegment(maxRecordsCount: 50)
        let records1 = try generateEnrichedRecordJSONs(for: segment1)
        let records2 = try generateEnrichedRecordJSONs(for: segment2)

        // When
        let segments = try builder.segments(from: records1 + records2).map { $0.toJSONObject() }

        // Then
        DDAssertJSONEqual(AnyEncodable(segments.first), segment1)
        DDAssertJSONEqual(AnyEncodable(segments.last), segment2)
    }

    func testWhenBuildingSegmentWithNoRecords_itThrows() {
        // When
        XCTAssertThrowsError(try builder.segments(from: [])) { error in
            // Then
            XCTAssertEqual((error as? SegmentJSONBuilderError)?.description, "Records array must not be empty.")
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
        let context = Recorder.Context(
            privacy: .mockRandom(),
            rumContext: RUMContext(
                applicationID: segment.application.id,
                sessionID: segment.session.id,
                viewID: segment.view.id,
                viewServerTimeOffset: 0
            )
        )

        let encoder = JSONEncoder()
        return try segment.records
            // To make it more challenging for tested `SegmentJSONBuilder`, we chunk records in
            // expected `segment`, so they are spread among many enriched records:
            .chunkedRandomly(numberOfChunks: .random(in: 1...segment.records.count))
            .map { EnrichedRecord(context: context, records: $0) }
            // Encode `EnrichedRecords` into `Data`, just like it happens in `DatadogCore` when
            // writting them into batches:
            .map { try encoder.encode($0) }
            // Decode it back to `EnrichedRecordJSON` just like it happens when preparing
            // upload requests for SR:
            .map { try EnrichedRecordJSON(jsonObjectData: $0) }
    }
}
