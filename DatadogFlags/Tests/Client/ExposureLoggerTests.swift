/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class ExposureLoggerTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testLogExposure() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope
        )

        let serverTimeOffset: TimeInterval = 1
        featureScope.contextMock.serverTimeOffset = serverTimeOffset

        // When
        logger.logExposure(
            for: "some-flag",
            assignment: .init(
                allocationKey: "allocation-123",
                variationKey: "variation-123",
                variation: .mockAnyBoolean(),
                reason: .mockAny(),
                doLog: true
            ),
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertEqual(
            featureScope.exposureEventsWritten,
            [
                .init(
                    timestamp: Date.mockAny()
                        .addingTimeInterval(serverTimeOffset)
                        .timeIntervalSince1970
                        .dd.toInt64Milliseconds,
                    allocation: .init(key: "allocation-123"),
                    flag: .init(key: "some-flag"),
                    variant: .init(key: "variation-123"),
                    subject: .init(id: .mockAny(), attributes: .mockAny())
                )
            ]
        )
    }

    func testLogExposureLoggingDisabled() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(doLog: false),
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertTrue(featureScope.eventsWritten.isEmpty)
    }

    func testLogExposureDeduplication() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny()
        )
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 1)
    }

    func testLogExposureDifferentVariation() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let assignment1 = FlagAssignment.mockAnyBoolean()
        var assignment2 = assignment1
        assignment2.variationKey = "other-variation"

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: assignment1,
            evaluationContext: .mockAny()
        )
        logger.logExposure(
            for: .mockAny(),
            assignment: assignment2,
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Same flag with different variation should be not deduplicated")
    }

    func testLogExposureDifferentAllocation() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let assignment1 = FlagAssignment.mockAnyBoolean()
        var assignment2 = assignment1
        assignment2.allocationKey = "other-allocation"

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: assignment1,
            evaluationContext: .mockAny()
        )
        logger.logExposure(
            for: .mockAny(),
            assignment: assignment2,
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Same flag with different allocation should be not deduplicated")
    }

    func testLogExposureDifferentFlag() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny()
        )
        logger.logExposure(
            for: "other-flag",
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny()
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Different flags should be not deduplicated")
    }

    func testLogExposureDifferentTargeting() {
        // Given
        let logger = ExposureLogger(
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        // When
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny()
        )
        logger.logExposure(
            for: .mockAny(),
            assignment: .mockAnyBoolean(),
            evaluationContext: .init(targetingKey: "other-targeting", attributes: .mockAny())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Same flag with different targeting should be not deduplicated")
    }
}

extension FeatureScopeMock {
    fileprivate var exposureEventsWritten: [ExposureEvent] {
        eventsWritten.compactMap {
            $0 as? ExposureEvent
        }
    }
}
