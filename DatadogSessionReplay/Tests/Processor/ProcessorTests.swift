/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

private class WriterMock: Writing {
    var records: [EnrichedRecord] = []

    func write(nextRecord: EnrichedRecord) { records.append(nextRecord) }
    func startWriting(to featureScope: FeatureScope) {}
}

class ProcessorTests: XCTestCase {
    private let writer = WriterMock()

    // MARK: - Processing `ViewTreeSnapshots`

    func testWhenProcessingFirstViewTreeSnapshot_itWritesRecordsThatIndicateStartOfASegment() throws {
        let time = Date()
        let rum: RUMContext = .mockRandom()

        // Given
        let processor = Processor(queue: NoQueue(), writer: writer)
        let viewTree = generateSimpleViewTree()

        // When
        let snapshot = generateViewTreeSnapshot(for: viewTree, date: time, rumContext: rum)
        processor.process(viewTreeSnapshot: snapshot, touchSnapshot: nil)

        // Then
        XCTAssertEqual(writer.records.count, 1)

        let enrichedRecord = try XCTUnwrap(writer.records.first)
        XCTAssertEqual(enrichedRecord.applicationID, rum.applicationID)
        XCTAssertEqual(enrichedRecord.sessionID, rum.sessionID)
        XCTAssertEqual(enrichedRecord.viewID, rum.viewID)
        XCTAssertEqual(enrichedRecord.earliestTimestamp, time.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(enrichedRecord.latestTimestamp, time.timeIntervalSince1970.toInt64Milliseconds)

        XCTAssertEqual(enrichedRecord.records.count, 3, "Segment must start with 'meta' → 'focus' → 'full snapshot' records")
        XCTAssertTrue(enrichedRecord.records[0].isMetaRecord)
        XCTAssertTrue(enrichedRecord.records[1].isFocusRecord)
        XCTAssertTrue(enrichedRecord.records[2].isFullSnapshotRecord && enrichedRecord.hasFullSnapshot)
    }

    func testWhenRUMContextDoesNotChangeInSucceedingViewTreeSnapshots_itWritesRecordsThatContinueCurrentSegment() {
        let time = Date()
        let rum: RUMContext = .mockRandom()

        // Given
        let processor = Processor(queue: NoQueue(), writer: writer)
        let viewTree = generateSimpleViewTree()

        // When
        let snapshot1 = generateViewTreeSnapshot(for: viewTree, date: time, rumContext: rum)
        let snapshot2 = generateViewTreeSnapshot(for: morphed(viewTree: viewTree), date: time.addingTimeInterval(1), rumContext: rum)
        let snapshot3 = generateViewTreeSnapshot(for: morphed(viewTree: viewTree), date: time.addingTimeInterval(2), rumContext: rum)

        processor.process(viewTreeSnapshot: snapshot1, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot2, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot3, touchSnapshot: nil)

        // Then
        let enrichedRecords = writer.records
        XCTAssertEqual(writer.records.count, 3)

        XCTAssertEqual(enrichedRecords[0].records.count, 3, "Segment must start with 'meta' → 'focus' → 'full snapshot' records")
        XCTAssertTrue(enrichedRecords[0].records[0].isMetaRecord)
        XCTAssertTrue(enrichedRecords[0].records[1].isFocusRecord)
        XCTAssertTrue(enrichedRecords[0].records[2].isFullSnapshotRecord && enrichedRecords[0].hasFullSnapshot)

        XCTAssertEqual(enrichedRecords[1].records.count, 1, "It should follow with 'incremental snapshot' record")
        XCTAssertTrue(enrichedRecords[1].records[0].isIncrementalSnapshotRecord)

        XCTAssertEqual(enrichedRecords[2].records.count, 1, "It should follow with 'incremental snapshot' record")
        XCTAssertTrue(enrichedRecords[2].records[0].isIncrementalSnapshotRecord)

        enrichedRecords.enumerated().forEach { index, enrichedRecord in
            XCTAssertEqual(enrichedRecord.applicationID, rum.applicationID)
            XCTAssertEqual(enrichedRecord.sessionID, rum.sessionID)
            XCTAssertEqual(enrichedRecord.viewID, rum.viewID)

            let expectedTime = time.addingTimeInterval(TimeInterval(index))
            XCTAssertEqual(enrichedRecord.earliestTimestamp, expectedTime.timeIntervalSince1970.toInt64Milliseconds)
            XCTAssertEqual(enrichedRecord.latestTimestamp, expectedTime.timeIntervalSince1970.toInt64Milliseconds)
        }
    }

    func testWhenOrientationChanges_itWritesRecordsViewportResizeDataSegment() {
        let time = Date()
        let rum: RUMContext = .mockRandom()

        // Given
        let processor = Processor(queue: NoQueue(), writer: writer)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let rotatedView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))

        // When
        let snapshot1 = generateViewTreeSnapshot(for: view, date: time, rumContext: rum)
        let snapshot2 = generateViewTreeSnapshot(for: rotatedView, date: time.addingTimeInterval(1), rumContext: rum)

        processor.process(viewTreeSnapshot: snapshot1, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot2, touchSnapshot: nil)

        // Then
        let enrichedRecords = writer.records
        XCTAssertEqual(writer.records.count, 2)

        XCTAssertEqual(enrichedRecords[0].records.count, 3, "Segment must start with 'meta' → 'focus' → 'full snapshot' records")
        XCTAssertTrue(enrichedRecords[0].records[0].isMetaRecord)
        XCTAssertTrue(enrichedRecords[0].records[1].isFocusRecord)
        XCTAssertTrue(enrichedRecords[0].records[2].isFullSnapshotRecord && enrichedRecords[0].hasFullSnapshot)

        XCTAssertEqual(enrichedRecords[1].records.count, 2, "It should follow with two 'incremental snapshot' records")
        XCTAssertTrue(enrichedRecords[1].records[0].isIncrementalSnapshotRecord)
        XCTAssertTrue(enrichedRecords[1].records[1].isIncrementalSnapshotRecord)
        XCTAssertEqual(enrichedRecords[1].records[1].incrementalSnapshot?.viewportResizeData?.height, 100)
        XCTAssertEqual(enrichedRecords[1].records[1].incrementalSnapshot?.viewportResizeData?.width, 200)
    }

    func testWhenRUMContextChangesInSucceedingViewTreeSnapshots_itWritesRecordsThatIndicateNextSegments() {
        let time = Date()
        let rum1: RUMContext = .mockRandom()
        let rum2: RUMContext = .mockRandom()

        // Given
        let processor = Processor(queue: NoQueue(), writer: writer)
        let viewTree = generateSimpleViewTree()

        // When
        let snapshot1 = generateViewTreeSnapshot(for: viewTree, date: time, rumContext: rum1)
        let snapshot2 = generateViewTreeSnapshot(for: morphed(viewTree: viewTree), date: time.addingTimeInterval(1), rumContext: rum1)
        let snapshot3 = generateViewTreeSnapshot(for: morphed(viewTree: viewTree), date: time.addingTimeInterval(2), rumContext: rum2)
        let snapshot4 = generateViewTreeSnapshot(for: morphed(viewTree: viewTree), date: time.addingTimeInterval(3), rumContext: rum2)

        processor.process(viewTreeSnapshot: snapshot1, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot2, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot3, touchSnapshot: nil)
        processor.process(viewTreeSnapshot: snapshot4, touchSnapshot: nil)

        // Then
        let enrichedRecords = writer.records
        XCTAssertEqual(writer.records.count, 4)

        XCTAssertEqual(enrichedRecords[0].records.count, 3, "Segment must start with 'meta' → 'focus' → 'full snapshot' records")
        XCTAssertTrue(enrichedRecords[0].records[0].isMetaRecord)
        XCTAssertTrue(enrichedRecords[0].records[1].isFocusRecord)
        XCTAssertTrue(enrichedRecords[0].records[2].isFullSnapshotRecord && enrichedRecords[0].hasFullSnapshot)

        XCTAssertEqual(enrichedRecords[1].records.count, 1, "It should follow with 'incremental snapshot' record")
        XCTAssertTrue(enrichedRecords[1].records[0].isIncrementalSnapshotRecord)

        XCTAssertEqual(enrichedRecords[2].records.count, 3, "Next segment must start with 'meta' → 'focus' → 'full snapshot' records")
        XCTAssertTrue(enrichedRecords[2].records[0].isMetaRecord)
        XCTAssertTrue(enrichedRecords[2].records[1].isFocusRecord)
        XCTAssertTrue(enrichedRecords[2].records[2].isFullSnapshotRecord && enrichedRecords[2].hasFullSnapshot)

        XCTAssertEqual(enrichedRecords[3].records.count, 1, "Next segment should follow with 'incremental snapshot' record")
        XCTAssertTrue(enrichedRecords[3].records[0].isIncrementalSnapshotRecord)

        zip(enrichedRecords, [rum1, rum1, rum2, rum2]).forEach { enrichedRecord, expectedRUM in
            XCTAssertEqual(enrichedRecord.applicationID, expectedRUM.applicationID)
            XCTAssertEqual(enrichedRecord.sessionID, expectedRUM.sessionID)
            XCTAssertEqual(enrichedRecord.viewID, expectedRUM.viewID)
        }
    }

    // MARK: - Processing `TouchSnapshots`

    func testWhenProcessingTouchSnapshot_itWritesRecordsThatContinueCurrentSegment() throws {
        let earliestTouchTime = Date()
        let snapshotTime = earliestTouchTime.addingTimeInterval(5)
        let numberOfTouches = 10
        let rum: RUMContext = .mockRandom()

        // Given
        let processor = Processor(queue: NoQueue(), writer: writer)

        // When
        let touchSnapshot = generateTouchSnapshot(startAt: earliestTouchTime, endAt: snapshotTime, numberOfTouches: numberOfTouches)
        processor.process(viewTreeSnapshot: .mockWith(date: snapshotTime, rumContext: rum), touchSnapshot: touchSnapshot)

        // Then
        XCTAssertEqual(writer.records.count, 1)

        let enrichedRecord = try XCTUnwrap(writer.records.first)
        XCTAssertEqual(enrichedRecord.applicationID, rum.applicationID)
        XCTAssertEqual(enrichedRecord.sessionID, rum.sessionID)
        XCTAssertEqual(enrichedRecord.viewID, rum.viewID)
        XCTAssertEqual(enrichedRecord.earliestTimestamp, earliestTouchTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(enrichedRecord.latestTimestamp, snapshotTime.timeIntervalSince1970.toInt64Milliseconds)

        XCTAssertEqual(enrichedRecord.records.count, 13)
        XCTAssertTrue(
            enrichedRecord.records[0].isMetaRecord &&
            enrichedRecord.records[1].isFocusRecord &&
            enrichedRecord.records[2].isFullSnapshotRecord && enrichedRecord.hasFullSnapshot,
            "Segment must start with 'meta' → 'focus' → 'full snapshot' records"
        )

        try enrichedRecord.records[3..<13].forEach { record in
            let pointerInteractionData = try XCTUnwrap(
                record.incrementalSnapshot?.pointerInteractionData,
                "Touch information must be send in 'incremental snapshot'"
            )
            XCTAssertEqual(pointerInteractionData.pointerType, .touch)
            XCTAssertGreaterThanOrEqual(record.timestamp, earliestTouchTime.timeIntervalSince1970.toInt64Milliseconds)
            XCTAssertLessThanOrEqual(record.timestamp, snapshotTime.timeIntervalSince1970.toInt64Milliseconds)
        }
    }

    // MARK: - `ViewTreeSnapshot` generation

    private let snapshotBuilder = ViewTreeSnapshotBuilder()

    private func generateViewTreeSnapshot(for viewTree: UIView, date: Date, rumContext: RUMContext) -> ViewTreeSnapshot {
        snapshotBuilder.createSnapshot(of: viewTree, with: .init(date: date, privacy: .allowAll, rumContext: rumContext))
    }

    private func generateSimpleViewTree() -> UIView {
        let root = UIView.mock(withFixture: .visible(.noAppearance))
        let child = UIView.mock(withFixture: .visible(.noAppearance))
        root.addSubview(child)
        return root
    }

    /// Alters the state of given `viewTree` a little bit so its next snapshot will include some changes.
    /// Returns altered `viewTree` for convenience (although mutation is applied in place through reference type).
    private func morphed(viewTree: UIView) -> UIView {
        var childFrame = viewTree.subviews.first?.frame ?? .zero
        childFrame = childFrame.applying(.init(translationX: .mockRandom(min: 1, max: 10), y: .mockRandom(min: 1, max: 10)))
        viewTree.subviews.first?.frame = childFrame
        return viewTree
    }

    // MARK: - `TouchSnapshot` generation

    private func generateTouchSnapshot(startAt startTime: Date, endAt endTime: Date, numberOfTouches: Int) -> TouchSnapshot {
        let dt = endTime.timeIntervalSince(startTime)
        return TouchSnapshot(
            date: startTime,
            touches: (0..<numberOfTouches).map { index in
                    .init(
                        id: .mockRandom(min: 0, max: TouchIdentifier(numberOfTouches)),
                        phase: [.down, .move, .up].randomElement()!,
                        date: startTime.addingTimeInterval(Double(index) * (dt / Double(numberOfTouches))),
                        position: .mockRandom()
                    )
            }
        )
    }
}
