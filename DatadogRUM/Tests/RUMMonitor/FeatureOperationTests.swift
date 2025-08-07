/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class FeatureOperationTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private let dateProvider = DateProviderMock()
    private let writer = FileWriterMock()
    private let opName = "test_feature"
    private let operationKey = "operation_123"
    private let opAttributes: [AttributeKey: AttributeValue] = ["key": "value"]

    private lazy var monitor = Monitor(
        dependencies: .mockWith(featureScope: featureScope),
        dateProvider: dateProvider
    )

    // MARK: - startFeatureOperation Tests

    func testStartFeatureOperation_ProcessesStartCommand() {
        // When
        monitor.startFeatureOperation(name: opName)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertNil(vitalEvent?.vital.operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .start)
        XCTAssertNil(vitalEvent?.vital.failureReason)
    }

    func testStartFeatureOperation_WithOperationKey_ProcessesStartCommand() {
        // When
        let operationKey: String? = .mockRandom()
        monitor.startFeatureOperation(name: opName, operationKey: operationKey, attributes: opAttributes)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertEqual(vitalEvent?.vital.operationKey, operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .start)
        XCTAssertNil(vitalEvent?.vital.failureReason)
        XCTAssertEqual(vitalEvent?.context?.contextInfo["key"] as? String, "value")
    }

    func testStartFeatureOperation_GeneratesUniqueVitalId() {
        // When
        monitor.startFeatureOperation(name: opName, operationKey: nil, attributes: [:])
        monitor.startFeatureOperation(name: opName, operationKey: nil, attributes: [:])

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let vitalEvent1 = vitalEvents[0]
        let vitalEvent2 = vitalEvents[1]

        XCTAssertNotNil(vitalEvent1.vital.id)
        XCTAssertNotNil(vitalEvent2.vital.id)
        XCTAssertNotEqual(vitalEvent1.vital.id, vitalEvent2.vital.id)
    }

    // MARK: - succeedFeatureOperation Tests

    func testSucceedFeatureOperation_ProcessesEndCommand() {
        // When
        monitor.succeedFeatureOperation(name: opName)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertNil(vitalEvent?.vital.operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .end)
        XCTAssertNil(vitalEvent?.vital.failureReason)
    }

    func testSucceedFeatureOperation_WithOperationKey_ProcessesEndCommand() {
        // When
        monitor.succeedFeatureOperation(name: opName, operationKey: operationKey, attributes: opAttributes)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertEqual(vitalEvent?.vital.operationKey, operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .end)
        XCTAssertNil(vitalEvent?.vital.failureReason)
        XCTAssertEqual(vitalEvent?.context?.contextInfo["key"] as? String, "value")
    }

    // MARK: - failFeatureOperation Tests

    func testFailFeatureOperation_ProcessesFailureCommand() {
        // Given
        let reason: RUMFeatureOperationFailureReason = .mockRandom()

        // When
        monitor.failFeatureOperation(name: opName, reason: reason)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertNil(vitalEvent?.vital.operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .end)
        XCTAssertEqual(vitalEvent?.vital.failureReason, reason)
    }

    func testFailFeatureOperation_WithOperationKey_ProcessesFailureCommand() {
        // Given
        let reason: RUMFeatureOperationFailureReason = .mockRandom()

        // When
        monitor.failFeatureOperation(name: opName, operationKey: operationKey, reason: reason, attributes: opAttributes)

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 1)

        let vitalEvent = vitalEvents.first
        XCTAssertNotNil(vitalEvent)
        XCTAssertEqual(vitalEvent?.vital.name, opName)
        XCTAssertEqual(vitalEvent?.vital.operationKey, operationKey)
        XCTAssertEqual(vitalEvent?.vital.type, .operationStep)
        XCTAssertEqual(vitalEvent?.vital.stepType, .end)
        XCTAssertEqual(vitalEvent?.vital.failureReason, reason)
        XCTAssertEqual(vitalEvent?.context?.contextInfo["key"] as? String, "value")
    }

    // MARK: - Feature Operation Lifecycle Tests

    func testFeatureOperationLifecycle_CompleteFlow() {
        // Given
        let opName: String = .mockRandom()
        let operationKey: String? = .mockRandom()

        // When - complete feature lifecycle
        monitor.startFeatureOperation(name: opName, operationKey: operationKey, attributes: ["start": "value"])
        monitor.succeedFeatureOperation(name: opName, operationKey: operationKey, attributes: ["success": "value"])

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let startEvent = vitalEvents[0]
        let endEvent = vitalEvents[1]

        XCTAssertEqual(startEvent.vital.name, opName)
        XCTAssertEqual(endEvent.vital.name, opName)
        XCTAssertEqual(startEvent.vital.operationKey, operationKey)
        XCTAssertEqual(endEvent.vital.operationKey, operationKey)
        XCTAssertEqual(startEvent.vital.type, .operationStep)
        XCTAssertEqual(endEvent.vital.type, .operationStep)
        XCTAssertEqual(startEvent.vital.stepType, .start)
        XCTAssertEqual(endEvent.vital.stepType, .end)
        XCTAssertEqual(startEvent.context?.contextInfo["start"] as? String, "value")
        XCTAssertEqual(endEvent.context?.contextInfo["success"] as? String, "value")
    }

    func testFeatureOperationLifecycle_WithFailure() {
        // Given
        let opName: String = .mockRandom()
        let operationKey: String? = .mockRandom()
        let opFailureError: RUMFeatureOperationFailureReason = .mockRandom()

        // When - feature lifecycle with failure
        monitor.startFeatureOperation(name: opName, operationKey: operationKey, attributes: ["start": "value"])
        monitor.failFeatureOperation(name: opName, operationKey: operationKey, reason: opFailureError, attributes: ["failure": "value"])

        // Then
        let vitalEvents = featureScope.eventsWritten(ofType: RUMVitalEvent.self)
        XCTAssertEqual(vitalEvents.count, 2)

        let startEvent = vitalEvents[0]
        let failureEvent = vitalEvents[1]

        XCTAssertEqual(startEvent.vital.name, opName)
        XCTAssertEqual(failureEvent.vital.name, opName)
        XCTAssertEqual(startEvent.vital.operationKey, operationKey)
        XCTAssertEqual(failureEvent.vital.operationKey, operationKey)
        XCTAssertEqual(startEvent.vital.type, .operationStep)
        XCTAssertEqual(failureEvent.vital.type, .operationStep)
        XCTAssertEqual(startEvent.vital.stepType, .start)
        XCTAssertEqual(failureEvent.vital.stepType, .end)
        XCTAssertEqual(failureEvent.vital.failureReason, opFailureError)
        XCTAssertEqual(startEvent.context?.contextInfo["start"] as? String, "value")
        XCTAssertEqual(failureEvent.context?.contextInfo["failure"] as? String, "value")
    }
}
