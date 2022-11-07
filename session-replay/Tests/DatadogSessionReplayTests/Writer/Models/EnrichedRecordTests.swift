/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class EnrichedRecordTests: XCTestCase {
    func testItHasFullSnapshot() {
        // Given
        let fullSnapshotRecordType = SRFullSnapshotRecord.mockRandom().type
        let recordsWithFSR: [SRRecord] = .mockRandom() + [.fullSnapshotRecord(value: .mockRandom())]
        let recordsWithNoFSR: [SRRecord] = .mockRandom().filter { $0.type != fullSnapshotRecordType }

        // When
        let enrichedRecords1 = EnrichedRecord(
            rumContext: .mockAny(),
            records: recordsWithFSR
        )
        let enrichedRecords2 = EnrichedRecord(
            rumContext: .mockAny(),
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
        let enrichedRecords = EnrichedRecord(
            rumContext: .mockAny(),
            records: records
        )

        // Then
//        XCTAssertEqual(enrichedRecords.earliestTimestamp, records.map({ $0.timestamp }).reduce(.max, min))
//        XCTAssertEqual(enrichedRecords.latestTimestamp, records.map({ $0.timestamp }).reduce(.min, max))
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
