/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

class ViewUpdateTrackerTests: XCTestCase {

    // MARK: - First Capture (No Previous State)

    func testFirstCapture_returnsSnapshot() {
        var tracker = ViewUpdateTracker()

        let snapshot = tracker.capture(
            timeSpent: 1000,
            actionCount: 1,
            errorCount: 0,
            resourceCount: 2,
            longTaskCount: 0,
            frozenFrameCount: 0,
            frustrationCount: 0
        )

        XCTAssertEqual(snapshot.timeSpent, 1000)
        XCTAssertEqual(snapshot.actionCount, 1)
        XCTAssertEqual(snapshot.resourceCount, 2)
    }

    func testChangedFields_whenNoPreviousState_returnsIsFirstUpdateTrue() {
        var tracker = ViewUpdateTracker()
        let snapshot = tracker.capture(timeSpent: 1000, actionCount: 0, errorCount: 0,
                                       resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let changes = tracker.changedFields(current: snapshot)

        XCTAssertTrue(changes.isFirstUpdate)
    }

    // MARK: - Subsequent Captures (Diff Detection)

    func testChangedFields_detectsTimeSpentChange() {
        var tracker = ViewUpdateTracker()

        // First capture
        _ = tracker.capture(timeSpent: 1000, actionCount: 0, errorCount: 0,
                           resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        // Second capture with changed timeSpent
        let snapshot2 = tracker.capture(timeSpent: 2000, actionCount: 0, errorCount: 0,
                                        resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let changes = tracker.changedFields(current: snapshot2)

        XCTAssertFalse(changes.isFirstUpdate)
        XCTAssertEqual(changes.timeSpent, 2000)
        XCTAssertNil(changes.actionCount)  // Unchanged
        XCTAssertTrue(changes.hasChanges)
    }

    func testChangedFields_detectsMultipleChanges() {
        var tracker = ViewUpdateTracker()

        _ = tracker.capture(timeSpent: 1000, actionCount: 0, errorCount: 0,
                           resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let snapshot2 = tracker.capture(timeSpent: 2000, actionCount: 1, errorCount: 2,
                                        resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let changes = tracker.changedFields(current: snapshot2)

        XCTAssertEqual(changes.timeSpent, 2000)
        XCTAssertEqual(changes.actionCount, 1)
        XCTAssertEqual(changes.errorCount, 2)
        XCTAssertNil(changes.resourceCount)  // Unchanged
    }

    func testChangedFields_whenNoChanges_hasChangesFalse() {
        var tracker = ViewUpdateTracker()

        _ = tracker.capture(timeSpent: 1000, actionCount: 1, errorCount: 0,
                           resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let snapshot2 = tracker.capture(timeSpent: 1000, actionCount: 1, errorCount: 0,
                                        resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let changes = tracker.changedFields(current: snapshot2)

        XCTAssertFalse(changes.hasChanges)
    }

    // MARK: - All Fields Coverage

    func testChangedFields_detectsAllFieldTypes() {
        var tracker = ViewUpdateTracker()

        _ = tracker.capture(timeSpent: 0, actionCount: 0, errorCount: 0,
                           resourceCount: 0, longTaskCount: 0, frozenFrameCount: 0, frustrationCount: 0)

        let snapshot2 = tracker.capture(timeSpent: 1, actionCount: 2, errorCount: 3,
                                        resourceCount: 4, longTaskCount: 5, frozenFrameCount: 6, frustrationCount: 7)

        let changes = tracker.changedFields(current: snapshot2)

        XCTAssertEqual(changes.timeSpent, 1)
        XCTAssertEqual(changes.actionCount, 2)
        XCTAssertEqual(changes.errorCount, 3)
        XCTAssertEqual(changes.resourceCount, 4)
        XCTAssertEqual(changes.longTaskCount, 5)
        XCTAssertEqual(changes.frozenFrameCount, 6)
        XCTAssertEqual(changes.frustrationCount, 7)
    }
}
