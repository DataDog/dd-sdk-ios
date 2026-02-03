/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@_spi(Internal)
@testable import DatadogCore

class ContextSharingTransformerTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testReceiveContextMessage_transformsToSharedContext() throws {
        // Given
        let transformer = ContextSharingTransformer()
        let message = FeatureMessage.context(.mockRandom())

        // When
        let handled = transformer.receive(message: message, from: core)

        // Then
        XCTAssertTrue(handled)
    }

    func testReceiveNonContextMessage_returnsNotHandled() throws {
        // Given
        let transformer = ContextSharingTransformer()
        let customMessage = FeatureMessage.payload("")

        // When
        let handled = transformer.receive(message: customMessage, from: core)

        // Then
        XCTAssertFalse(handled)
    }

    func testPublish_callsReceiverImmediately() throws {
        // Given
        let transformer = ContextSharingTransformer()
        let expectation = expectation(description: "receiver is called")
        var receivedContext: SharedContext?

        // When
        transformer.publish { context in
            receivedContext = context
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertNil(receivedContext) // Initially nil
    }

    func testPublish_callsReceiverOnContextUpdate() throws {
        // Given
        let transformer = ContextSharingTransformer()
        let expectation = expectation(description: "receiver is called with new context")
        expectation.expectedFulfillmentCount = 2 // Initial nil + update

        var receivedContexts: [SharedContext?] = []

        transformer.publish { context in
            receivedContexts.append(context)
            expectation.fulfill()
        }

        // When
        let userInfo = UserInfo(id: "user-456")
        let accountInfo = AccountInfo(id: "account-789")
        let context = DatadogContext.mockWith(userInfo: userInfo, accountInfo: accountInfo)
        let message = FeatureMessage.context(context)
        _ = transformer.receive(message: message, from: core)

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(receivedContexts.count, 2)
        XCTAssertNil(receivedContexts[0])
        XCTAssertEqual(receivedContexts[1]?.userId, "user-456")
        XCTAssertEqual(receivedContexts[1]?.accountId, "account-789")
    }

    func testCancel_removesReceiver() throws {
        // Given
        let transformer = ContextSharingTransformer()
        let expectation = expectation(description: "receiver is not called after cancel")
        expectation.isInverted = true

        var callCount = 0

        transformer.publish { _ in
            callCount += 1
            if callCount > 1 {
                expectation.fulfill()
            }
        }

        // When
        transformer.cancel()

        let context = DatadogContext.mockWith(userInfo: UserInfo(id: "user-789"))
        let message = FeatureMessage.context(context)
        _ = transformer.receive(message: message, from: core)

        // Then
        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(callCount, 1) // Only initial call
    }
}
