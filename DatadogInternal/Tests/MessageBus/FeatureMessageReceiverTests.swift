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
        func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
            expectation?.fulfill()
            return true
        }
    }

    func testNOPReceiver_returnsFalse() {
        let receiver = NOPFeatureMessageReceiver()
        XCTAssertFalse(receiver.receive(message: .custom(key: .mockAny(), baggage: [:]), from: core))
        XCTAssertFalse(receiver.receive(message: .context(.mockRandom()), from: core))
    }

    func testEmptyCombinedReceiver_returnsFalse() {
        let receiver = CombinedFeatureMessageReceiver([])
        XCTAssertFalse(receiver.receive(message: .custom(key: .mockAny(), baggage: [:]), from: core))
        XCTAssertFalse(receiver.receive(message: .context(.mockRandom()), from: core))
    }

    func testCombinedReceiver_withValidReceiver_returnsTrue() {
        let expectation = expectation(description: "receive 2 messages")
        expectation.expectedFulfillmentCount = 2

        let receiver = CombinedFeatureMessageReceiver(
            NOPFeatureMessageReceiver(),
            TestReceiver(expectation: expectation)
        )

        XCTAssertTrue(receiver.receive(message: .custom(key: .mockAny(), baggage: [:]), from: core))
        XCTAssertTrue(receiver.receive(message: .context(.mockRandom()), from: core))
        waitForExpectations(timeout: 0)
    }

    func testCombinedReceiver_withMultiValidReceiver_itSendsToFirstOnly() {
        let expectation = self.expectation(description: "receive message")
        let noExpectation = self.expectation(description: "do not receive message")
        noExpectation.isInverted = true

        let receiver = CombinedFeatureMessageReceiver(
            TestReceiver(expectation: expectation),
            TestReceiver(expectation: noExpectation)
        )

        XCTAssertTrue(receiver.receive(message: .custom(key: .mockAny(), baggage: [:]), from: core))
        waitForExpectations(timeout: 0)
    }
}
