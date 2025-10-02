/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities

@testable import DatadogRUM

class FlagExposureReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testReceiveFlagExposureMessage() throws {
        // Given
        let receiver = FlagExposureReceiver(
            monitor: Monitor(
                dependencies: .mockWith(featureScope: featureScope),
                dateProvider: SystemDateProvider()
            )
        )
        let timestamp = TimeInterval.mockAny()
        let message: FeatureMessage = .payload(
            RUMFlagExposureMessage(
                timestamp: timestamp,
                flagKey: "feature-flag",
                allocationKey: "allocation-123",
                exposureKey: "feature-flag-allocation-123",
                subjectKey: "user-123",
                variantKey: "variation-456",
                subjectAttributes: ["email": "test@example.com", "plan": "premium"]
            )
        )

        // When
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        let event: RUMActionEvent = try XCTUnwrap(featureScope.eventsWritten().last, "It should send action event")
        XCTAssertEqual(event.action.type, .custom)
        XCTAssertEqual(event.action.target?.name, "__dd_exposure")

        let contextInfo = try XCTUnwrap(event.context?.contextInfo)
        XCTAssertEqual(contextInfo["timestamp"] as? Int64, timestamp.toInt64Milliseconds)
        XCTAssertEqual(contextInfo["flag_key"] as? String, "feature-flag")
        XCTAssertEqual(contextInfo["allocation_key"] as? String, "allocation-123")
        XCTAssertEqual(contextInfo["exposure_key"] as? String, "feature-flag-allocation-123")
        XCTAssertEqual(contextInfo["subject_key"] as? String, "user-123")
        XCTAssertEqual(contextInfo["variant_key"] as? String, "variation-456")
        XCTAssertNotNil(contextInfo["subject_attributes"], "subject_attributes should be present")
    }
}
