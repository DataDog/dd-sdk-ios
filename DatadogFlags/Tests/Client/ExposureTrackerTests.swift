/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@_spi(Internal)
@testable import DatadogFlags

final class ExposureTrackerTests: XCTestCase {
    func testItEvictsLeastRecentlyUsedAssignmentWhenCountLimitIsExceeded() {
        // Given
        let tracker = ExposureTracker(countLimit: 2)
        let exposure1 = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a"
        )
        let exposure2 = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-2",
            allocationKey: "allocation-a",
            variationKey: "variation-a"
        )
        let exposure3 = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-3",
            allocationKey: "allocation-a",
            variationKey: "variation-a"
        )

        // When
        XCTAssertTrue(tracker.track(exposure1))
        XCTAssertTrue(tracker.track(exposure2))
        XCTAssertFalse(tracker.track(exposure1))
        XCTAssertTrue(tracker.track(exposure3))

        // Then
        XCTAssertFalse(tracker.track(exposure1), "Recently used exposure should remain cached")
        XCTAssertTrue(tracker.track(exposure2), "Least recently used exposure should be evicted")
    }

    func testItTracksTwoSubjectsAcrossManyFlags() {
        // Given
        let tracker = ExposureTracker()
        let targetingKeys = ["subject-1", "subject-2"]
        let flagKeys = (0..<2_500).map { "flag-\($0)" }

        // Then
        for targetingKey in targetingKeys {
            for flagKey in flagKeys {
                XCTAssertTrue(
                    tracker.track(
                        .init(
                            targetingKey: targetingKey,
                            flagKey: flagKey,
                            allocationKey: "allocation-a",
                            variationKey: "variation-a"
                        )
                    )
                )
            }
        }

        for targetingKey in targetingKeys {
            for flagKey in flagKeys {
                XCTAssertFalse(
                    tracker.track(
                        .init(
                            targetingKey: targetingKey,
                            flagKey: flagKey,
                            allocationKey: "allocation-a",
                            variationKey: "variation-a"
                        )
                    )
                )
            }
        }
    }
}
