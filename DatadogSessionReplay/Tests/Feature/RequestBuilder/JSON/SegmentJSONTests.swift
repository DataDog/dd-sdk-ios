/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogSessionReplay

class SegmentJSONTests: XCTestCase {
    func testGivenSRSegmentWithRecords_whenCreatingSegmentJSON_itEcodesToTheSameJSON() throws {
        // Given
        let source: SRSegment.Source = .mockRandom()
        let segment1 = generateSegment(maxRecordsCount: 50, source: source)
        let segment2 = generateSegment(maxRecordsCount: 50, source: source)
        let segments1 = try generateEnrichedRecordJSONs(for: segment1)
        let segments2 = try generateEnrichedRecordJSONs(for: segment2)

        // When
        let segments = (segments1 + segments2).merge().map { $0.toJSONObject() }

        // Then
        DDAssertJSONEqual(AnyEncodable(segments.first), segment1)
        DDAssertJSONEqual(AnyEncodable(segments.last), segment2)
    }

    func testWhenDecodingEnrichedRecordData_itHasTheSameInformationAvailable() throws {
        // Given
        let enrichedRecords = EnrichedRecord(
            context: .mockRandom(),
            records: .mockRandom()
        )
        let data = try encode(enrichedRecords)

        // When
        let segment = try SegmentJSON(data, source: .mockAny())

        // Then
        XCTAssertEqual(segment.applicationID, enrichedRecords.applicationID)
        XCTAssertEqual(segment.sessionID, enrichedRecords.sessionID)
        XCTAssertEqual(segment.viewID, enrichedRecords.viewID)
        XCTAssertEqual(segment.records.count, enrichedRecords.records.count)
        XCTAssertEqual(segment.start, enrichedRecords.records.map({ $0.timestamp }).min())
        XCTAssertEqual(segment.end, enrichedRecords.records.map({ $0.timestamp }).max())

        let expected = try encode(enrichedRecords.records)
        let actual = try encode(segment.records)
        XCTAssertEqual(expected, actual, "Serialized records data must be equal in both `EnrichedRecord` and `EnrichedRecordJSON`")
    }

    func testWhenDecodingMalformedData_itThrows() {
        // Given
        let malrofmedData1 = "[]".data(using: .utf8)!
        let malrofmedData2 = "{}".data(using: .utf8)!

        // When & Then
        XCTAssertThrowsError(try SegmentJSON(malrofmedData1, source: .mockRandom())) { error in
            let description = (error as! DatadogSessionReplay.InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to decode Dictionary<String, Any>.Type"))
        }
        XCTAssertThrowsError(try SegmentJSON(malrofmedData2, source: .mockRandom())) { error in
            let description = (error as! DatadogSessionReplay.InternalError).description
            XCTAssertTrue(description.hasPrefix("Failed to read attribute at key path"))
        }
    }

    func testItHasFullSnapshot() throws {
        // Given
        let encoder = JSONEncoder()
        let recordsWithFSR: [SRRecord] = .mockRandom() + [.fullSnapshotRecord(value: .mockRandom())]
        let recordsWithNoFSR: [SRRecord] = .mockRandom().filter { !$0.isFullSnapshotRecord }

        let enrichedRecords1 = EnrichedRecord(
            context: .mockAny(),
            records: recordsWithFSR
        )
        let enrichedRecords2 = EnrichedRecord(
            context: .mockAny(),
            records: recordsWithNoFSR
        )

        let data1 = try encoder.encode(enrichedRecords1)
        let data2 = try encoder.encode(enrichedRecords2)

        // When
        let segment1 = try SegmentJSON(data1, source: .mockAny())
        let segment2 = try SegmentJSON(data2, source: .mockAny())

        // Then
        XCTAssertTrue(segment1.hasFullSnapshot)
        XCTAssertFalse(segment2.hasFullSnapshot)
    }

    func testItComputesEarliestAndLatestTimestamps() throws {
        // Given
        let encoder = JSONEncoder()

        let record = EnrichedRecord(
            context: .mockAny(),
            records: .mockRandom(count: .mockRandom(min: 1, max: 100))
        )

        let data = try encoder.encode(record)

        // When
        let segment = try SegmentJSON(data, source: .mockAny())

        // Then
        XCTAssertEqual(segment.start, record.records.map({ $0.timestamp }).min())
        XCTAssertEqual(segment.end, record.records.map({ $0.timestamp }).max())
    }

    // MARK: - Fuzzy Helpers

    private func generateSegment(maxRecordsCount: Int64 = 100, source: SRSegment.Source = .mockRandom()) -> SRSegment {
        let recordsCount: Int64 = .mockRandom(min: 1, max: maxRecordsCount)
        let records: [SRRecord] = (0..<recordsCount).map { _ in .mockRandom() }
        let timestamps = records.map { $0.timestamp }
        let hasFullSnapshot = records.contains {
            switch $0 {
            case .fullSnapshotRecord: return true
            default: return false
            }
        }

        return SRSegment(
            application: .init(id: .mockRandom()),
            end: timestamps.min(by: >)!,
            hasFullSnapshot: hasFullSnapshot,
            indexInView: nil,
            records: records,
            recordsCount: recordsCount,
            session: .init(id: .mockRandom()),
            source: source,
            start: timestamps.min(by: <)!,
            view: .init(id: .mockRandom())
        )
    }

    private func generateEnrichedRecordJSONs(for segment: SRSegment) throws -> [SegmentJSON] {
        let context = Recorder.Context(
            privacy: .mockRandom(),
            textAndInputPrivacy: .mockRandom(),
            touchPrivacy: .mockRandom(),
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
            .map { try SegmentJSON($0, source: segment.source) }
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
#endif
