/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class RUMInstrumentationTests: XCTestCase {
    private var config = RUM.Configuration(applicationID: .mockAny())

    func testWhenOnlyUIKitViewsPredicateIsConfigured_itInstrumentsUIViewController() throws {
        // When
        let instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
            uiKitRUMActionsPredicate: nil,
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            telemetry: NOPTelemetry()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings([
                "viewDidAppear:",
                "viewDidDisappear:",
            ])
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testWhenOnlyUIKitActionsPredicateIsConfigured_itInstrumentsUIApplication() throws {
        // When
        let instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMActionsPredicate: UIKitRUMActionsPredicateMock(),
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            telemetry: NOPTelemetry()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings(["sendEvent:"])
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testWhenOnlyLongTasksThresholdIsConfigured_itInstrumentsRunLoop() throws {
        // When
        let instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMActionsPredicate: nil,
            longTaskThreshold: 0.5,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            telemetry: NOPTelemetry()
        )

        // Then
        try withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings([])
            let beginRunLoopObserver = try XCTUnwrap(instrumentation.longTasks?.observer_begin)
            let endRunLoopObserver = try XCTUnwrap(instrumentation.longTasks?.observer_end)
            XCTAssertTrue(CFRunLoopContainsObserver(RunLoop.main.getCFRunLoop(), beginRunLoopObserver, .commonModes))
            XCTAssertTrue(CFRunLoopContainsObserver(RunLoop.main.getCFRunLoop(), endRunLoopObserver, .commonModes))
        }
    }

    func testWhenLongTasksThresholdIsLessOrEqualZero_itDoesNotInstrumentsRunLoop() {
        // When
        let instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMActionsPredicate: nil,
            longTaskThreshold: .mockRandom(min: -100, max: 0),
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            telemetry: NOPTelemetry()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testGivenAllInstrumentationsConfigured_whenSubscribed_itSetsSubsciberInRespectiveHandlers() throws {
        // Given
        let instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
            uiKitRUMActionsPredicate: UIKitRUMActionsPredicateMock(),
            longTaskThreshold: 0.5,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            telemetry: NOPTelemetry()
        )
        let subscriber = RUMCommandSubscriberMock()

        // When
        instrumentation.publish(to: subscriber)

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertIdentical(instrumentation.viewsHandler.subscriber, subscriber)
            XCTAssertIdentical((instrumentation.actionsHandler as? UIKitRUMUserActionsHandler)?.subscriber, subscriber)
            XCTAssertIdentical(instrumentation.longTasks?.subscriber, subscriber)
        }
    }
}

internal func DDAssertActiveSwizzlings(_ expectedSwizzledSelectors: [String], file: StaticString = #filePath, line: UInt = #line) {
    _DDEvaluateAssertion(message: "Only \(expectedSwizzledSelectors) swizzlings should be active", file: file, line: line) {
        let actual = Swizzling.methods.map { "\(method_getName($0))" }.sorted()
        let expected = expectedSwizzledSelectors.sorted()

        guard actual == expected else {
            throw DDAssertError.expectedFailure("actual swizzlings: \(actual) don't match expected ones: \(expected)")
        }
    }
}
