/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import Datadog
@testable import DatadogSessionReplay

class RUMContextReceiverTests: XCTestCase {
    private let receiver = RUMContextReceiver()

    func testWhenMessageContainsNonEmptyRUMBaggage_itNotifiesRUMContext() {
        // Given
        let context = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.ids: [
                    RUMContext.IDs.CodingKeys.applicationID.rawValue: "app-id",
                    RUMContext.IDs.CodingKeys.sessionID.rawValue: "session-id",
                    RUMContext.IDs.CodingKeys.viewID.rawValue: "view-id"
                ],
                RUMDependency.serverTimeOffsetKey: TimeInterval(123)
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
        XCTAssertEqual(rumContext?.ids.applicationID, "app-id")
        XCTAssertEqual(rumContext?.ids.sessionID, "session-id")
        XCTAssertEqual(rumContext?.ids.viewID, "view-id")
        XCTAssertEqual(rumContext?.viewServerTimeOffset, 123)
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
                RUMDependency.ids: [
                    RUMContext.IDs.CodingKeys.applicationID.rawValue: "app-id-1",
                    RUMContext.IDs.CodingKeys.sessionID.rawValue: "session-id-1",
                    RUMContext.IDs.CodingKeys.viewID.rawValue: "view-id-1"
                ],
                RUMDependency.serverTimeOffsetKey: TimeInterval(123)
            ]
        ])
        let message1 = FeatureMessage.context(context1)
        let context2 = DatadogContext.mockWith(featuresAttributes: [
            RUMDependency.rumBaggageKey: [
                RUMDependency.ids: [
                    RUMContext.IDs.CodingKeys.applicationID.rawValue: "app-id-2",
                    RUMContext.IDs.CodingKeys.sessionID.rawValue: "session-id-2",
                    RUMContext.IDs.CodingKeys.viewID.rawValue: "view-id-2"
                ],
                RUMDependency.serverTimeOffsetKey: TimeInterval(345)
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
        XCTAssertEqual(rumContexts[0].ids.applicationID, "app-id-1")
        XCTAssertEqual(rumContexts[0].ids.sessionID, "session-id-1")
        XCTAssertEqual(rumContexts[0].ids.viewID, "view-id-1")
        XCTAssertEqual(rumContexts[0].viewServerTimeOffset, 123)
        XCTAssertEqual(rumContexts[1].ids.applicationID, "app-id-2")
        XCTAssertEqual(rumContexts[1].ids.sessionID, "session-id-2")
        XCTAssertEqual(rumContexts[1].ids.viewID, "view-id-2")
        XCTAssertEqual(rumContexts[1].viewServerTimeOffset, 345)
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
}
