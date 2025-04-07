/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

class RecordsBuilderTests: XCTestCase {
    func testWhenPreviousAndNextWireframesAreTheSame_itCreatesNoIncrementalSnapshotRecord() {
        let builder = RecordsBuilder(telemetry: TelemetryMock())

        // Given
        let wireframes: [SRWireframe] = .mockRandom()

        // When
        XCTAssertNil(
            builder.createIncrementalSnapshotRecord(from: .mockAny(), with: wireframes, lastWireframes: wireframes),
            "If wireframes did not change, it should return no record"
        )
    }

    func testWhenPreviousAndNextWireframesAreDifferent_itCreatesIncrementalSnapshotRecord() throws {
        let builder = RecordsBuilder(telemetry: TelemetryMock())

        // Given
        let previous: [SRWireframe] = [.mockRandomWith(id: 0), .mockRandomWith(id: 1)]
        let next: [SRWireframe] = previous + [.mockRandomWith(id: 2)]

        // When
        let record = builder.createIncrementalSnapshotRecord(from: .mockAny(), with: next, lastWireframes: previous)

        // Then
        let incrementalRecord = try XCTUnwrap(record?.incrementalSnapshot)
        guard case .mutationData(let mutations) = incrementalRecord.data else {
            XCTFail("Expected `mutationData` in incremental record, got \(incrementalRecord.data)")
            return
        }
        XCTAssertTrue(mutations.updates.isEmpty)
        XCTAssertTrue(mutations.removes.isEmpty)
        XCTAssertEqual(mutations.adds.count, 1)
        XCTAssertEqual(mutations.adds[0].previousId, 1)
        DDAssertReflectionEqual(mutations.adds[0].wireframe, next[2])
    }

    func testWhenNextWireframesAddsNewRoot_itCreatesIncrementalRecord() throws {
        let builder = RecordsBuilder(telemetry: TelemetryMock())

        // Given
        let previous: [SRWireframe] = [.mockRandomWith(id: 0), .mockRandomWith(id: 1)]
        let next: [SRWireframe] = [.mockRandomWith(id: 2)] + previous

        // When
        let record = builder.createIncrementalSnapshotRecord(from: .mockAny(), with: next, lastWireframes: previous)

        // Then
        let incrementalRecord = try XCTUnwrap(record?.incrementalSnapshot)
        guard case .mutationData = incrementalRecord.data else {
            XCTFail("Expected `mutationData` in incremental record, got \(incrementalRecord.data)")
            return
        }
    }

    // This case does not need a full snapshot for the player to work, but adding a
    // test documents the behavior if we want to change it.
    func testWhenNextWireframesDeletesRoot_itCreatesFullSnapshotRecord() throws {
        let builder = RecordsBuilder(telemetry: TelemetryMock())

        // Given
        let previous: [SRWireframe] = [
            .shapeWireframe(value: .mockRandomWith(id: 0)),
            .shapeWireframe(value: .mockRandomWith(id: 1))
        ]
        let next: [SRWireframe] = [.shapeWireframe(value: .mockRandomWith(id: 1))]

        // When
        let record = builder.createIncrementalSnapshotRecord(from: .mockAny(), with: next, lastWireframes: previous)

        // Then
        let incrementalRecord = try XCTUnwrap(record?.incrementalSnapshot)
        guard case .mutationData = incrementalRecord.data else {
            XCTFail("Expected `mutationData` in incremental record, got \(incrementalRecord.data)")
            return
        }
    }

    func testWhenWireframesAreNotConsistent_itFallbacksToFullSnapshotRecordAndSendsErrorTelemetry() throws {
        let telemetry = TelemetryMock()
        let builder = RecordsBuilder(telemetry: telemetry)

        // Given
        let previous: [SRWireframe] = [.shapeWireframe(value: .mockRandomWith(id: 1))]
        let next: [SRWireframe] = [.textWireframe(value: .mockRandomWith(id: 1))] // illegal: different wireframe type for the same ID

        // When
        let record = builder.createIncrementalSnapshotRecord(from: .mockAny(), with: next, lastWireframes: previous)

        // Then
        let fullRecord = try XCTUnwrap(record?.fullSnapshot)
        DDAssertReflectionEqual(fullRecord.data.wireframes, next)
        XCTAssertEqual(
            telemetry.description,
            """
            Telemetry logs:
             - [error] [SR] Failed to create incremental record - typeMismatch(fromType: "shape", toType: "text"), kind: WireframeMutationError, stack: typeMismatch(fromType: "shape", toType: "text")
            """
        )
    }
}
#endif
