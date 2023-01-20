/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

class RUMContextReceiverTests: XCTestCase {
    private let receiver = RUMContextReceiver()

    func testWhenMessageContainsNonEmptyRUMBaggage_itNotifiesRUMContext() {
        // Given
        let context = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.applicationIDKey: "app-id",
                RUMDependency.sessionIDKey: "session-id",
                RUMDependency.viewIDKey: "view-id",
                RUMDependency.serverTimeOffset: TimeInterval(123)
            ]
        ])
        let message = FeatureMessage.context(context)
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        var rumContext: RUMContext?
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }
        core.send(message: message, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })

        // Then
        XCTAssertEqual(rumContext?.applicationID, "app-id")
        XCTAssertEqual(rumContext?.sessionID, "session-id")
        XCTAssertEqual(rumContext?.viewID, "view-id")
        XCTAssertEqual(rumContext?.serverTimeOffset, 123)
    }

    func testWhenMessageContainsEmptyRUMBaggage_itNotifiesNoRUMContext() {
        let context = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [:]
        ])
        let message = FeatureMessage.context(context)
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        var rumContext: RUMContext?
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }
        core.send(message: message, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })

        // Then
        XCTAssertNil(rumContext)
    }

    func testWhenSucceedingMessagesContainDifferentRUMBaggages_itNotifiesRUMContextChange() {
        // Given
        let context1 = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.applicationIDKey: "app-id-1",
                RUMDependency.sessionIDKey: "session-id-1",
                RUMDependency.viewIDKey: "view-id-1",
                RUMDependency.serverTimeOffset: TimeInterval(123)
            ]
        ])
        let message1 = FeatureMessage.context(context1)
        let context2 = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.applicationIDKey: "app-id-2",
                RUMDependency.sessionIDKey: "session-id-2",
                RUMDependency.viewIDKey: "view-id-2",
                RUMDependency.serverTimeOffset: TimeInterval(345)
            ]
        ])
        let message2 = FeatureMessage.context(context2)
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        var rumContexts = [RUMContext]()
        receiver.observe(on: NoQueue()) { context in
            context.flatMap { rumContexts.append($0) }
        }
        core.send(message: message1, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })
        core.send(message: message2, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })

        // Then
        XCTAssertEqual(rumContexts.count, 2)
        XCTAssertEqual(rumContexts[0].applicationID, "app-id-1")
        XCTAssertEqual(rumContexts[0].sessionID, "session-id-1")
        XCTAssertEqual(rumContexts[0].viewID, "view-id-1")
        XCTAssertEqual(rumContexts[0].serverTimeOffset, 123)
        XCTAssertEqual(rumContexts[1].applicationID, "app-id-2")
        XCTAssertEqual(rumContexts[1].sessionID, "session-id-2")
        XCTAssertEqual(rumContexts[1].viewID, "view-id-2")
        XCTAssertEqual(rumContexts[1].serverTimeOffset, 345)
    }

    func testWhenMessageDoesntContainRUMBaggage_itCallsFallback() {
        let context = DatadogContext.mockAny()
        let message = FeatureMessage.context(context)
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        var fallbackCalled = false
        core.send(message: message, sender: core, else: {
            fallbackCalled = true
        })

        // Then
        XCTAssertTrue(fallbackCalled)
    }

    func testWhenSucceedingMessagesContainEqualRUMBaggages_itDoesNotNotifyRUMContextChange() {
        // Given
        let context = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.applicationIDKey: "app-id",
                RUMDependency.sessionIDKey: "session-id",
                RUMDependency.viewIDKey: "view-id",
                RUMDependency.serverTimeOffset: TimeInterval(123)
            ]
        ])
        let message = FeatureMessage.context(context)
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        var rumContexts = [RUMContext]()
        receiver.observe(on: NoQueue()) { context in
            context.flatMap { rumContexts.append($0) }
        }
        core.send(message: message, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })
        core.send(message: message, sender: core, else: {
            XCTFail("Fallback shouldn't be called")
        })

        // Then
        XCTAssertEqual(rumContexts.count, 1)
        XCTAssertEqual(rumContexts[0].applicationID, "app-id")
        XCTAssertEqual(rumContexts[0].sessionID, "session-id")
        XCTAssertEqual(rumContexts[0].viewID, "view-id")
        XCTAssertEqual(rumContexts[0].serverTimeOffset, 123)
    }
}
