/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

class FeatureMessageReceiverTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    struct TestReceiver: FeatureMessageReceiver {
        let expectation: XCTestExpectation?
        func receive(message: FeatureMessage) {
            expectation?.fulfill()
        }
    }

    func testNOPReceiver_doesNothing() throws {
        let receiver = NOPFeatureMessageReceiver()
        receiver.receive(message: .payload("test"))
        receiver.receive(message: .context(.mockRandom()))
    }

    func testEmptyCombinedReceiver_doesNothing() throws {
        let receiver = CombinedFeatureMessageReceiver([])
        receiver.receive(message: .payload("test"))
        receiver.receive(message: .context(.mockRandom()))
    }

    func testCombinedReceiver_withValidReceiver_forwardsMessages() throws {
        let expectation = expectation(description: "receive 2 messages")
        expectation.expectedFulfillmentCount = 2

        let receiver = CombinedFeatureMessageReceiver(
            NOPFeatureMessageReceiver(),
            TestReceiver(expectation: expectation)
        )

        receiver.receive(message: .payload("test"))
        receiver.receive(message: .context(.mockRandom()))
        waitForExpectations(timeout: 0)
    }

    func testCombinedReceiver_withMultiValidReceiver_itSendsToAll() throws {
        let expectation1 = self.expectation(description: "first receiver gets message")
        let expectation2 = self.expectation(description: "second receiver gets message")

        let receiver = CombinedFeatureMessageReceiver(
            TestReceiver(expectation: expectation1),
            TestReceiver(expectation: expectation2)
        )

        receiver.receive(message: .payload("test"))
        waitForExpectations(timeout: 0)
    }
}
