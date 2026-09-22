/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@_spi(Internal)
@testable import DatadogFlags

final class ExposureTrackerTests: XCTestCase {
    func testItSuppressesRepeatedAssignment() {
        // Given
        let tracker = ExposureTracker()
        let exposure = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: nil
        )

        // When
        let firstTrack = tracker.track(exposure)
        let secondTrack = tracker.track(exposure)

        // Then
        XCTAssertTrue(firstTrack)
        XCTAssertFalse(secondTrack)
    }

    func testItTracksAssignmentCycle() {
        // Given
        let tracker = ExposureTracker()
        let exposureA = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: nil
        )
        let exposureB = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-b",
            variationKey: "variation-b",
            serialID: nil
        )

        // When
        let firstTrack = tracker.track(exposureA)
        let secondTrack = tracker.track(exposureB)
        let thirdTrack = tracker.track(exposureA)

        // Then
        XCTAssertTrue(firstTrack)
        XCTAssertTrue(secondTrack)
        XCTAssertTrue(thirdTrack)
    }

    func testItTracksSerialIDAppearingOnAnUnchangedAssignment() {
        // Given
        let tracker = ExposureTracker()
        let withoutSerialID = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: nil
        )
        let withSerialID = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: 0
        )

        // When
        let firstTrack = tracker.track(withoutSerialID)
        let secondTrack = tracker.track(withSerialID)
        let thirdTrack = tracker.track(withSerialID)

        // Then
        XCTAssertTrue(firstTrack)
        XCTAssertTrue(secondTrack)
        XCTAssertFalse(thirdTrack)
    }

    func testItTracksSerialIDChangingOnAnUnchangedAssignment() {
        // Given
        let tracker = ExposureTracker()
        let exposureA = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: 340_132
        )
        let exposureB = ExposureTracker.Exposure(
            targetingKey: "subject-1",
            flagKey: "flag-1",
            allocationKey: "allocation-a",
            variationKey: "variation-a",
            serialID: 340_133
        )

        // When
        let firstTrack = tracker.track(exposureA)
        let secondTrack = tracker.track(exposureB)

        // Then
        XCTAssertTrue(firstTrack)
        XCTAssertTrue(secondTrack)
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
                            variationKey: "variation-a",
                            serialID: nil
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
                            variationKey: "variation-a",
                            serialID: nil
                        )
                    )
                )
            }
        }
    }
}
