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

    func testNOPReceiver_returnsFalse() throws {
        let receiver = NOPFeatureMessageReceiver()
        XCTAssertFalse(try receiver.receive(message: .baggage(key: .mockAny(), value: "test"), from: core))
        XCTAssertFalse(receiver.receive(message: .context(.mockRandom()), from: core))
    }

    func testEmptyCombinedReceiver_returnsFalse() throws {
        let receiver = CombinedFeatureMessageReceiver([])
        XCTAssertFalse(try receiver.receive(message: .baggage(key: .mockAny(), value: "test"), from: core))
        XCTAssertFalse(receiver.receive(message: .context(.mockRandom()), from: core))
    }

    func testCombinedReceiver_withValidReceiver_returnsTrue() throws {
        let expectation = expectation(description: "receive 2 messages")
        expectation.expectedFulfillmentCount = 2

        let receiver = CombinedFeatureMessageReceiver(
            NOPFeatureMessageReceiver(),
            TestReceiver(expectation: expectation)
        )

        XCTAssertTrue(try receiver.receive(message: .baggage(key: .mockAny(), value: "test"), from: core))
        XCTAssertTrue(receiver.receive(message: .context(.mockRandom()), from: core))
        waitForExpectations(timeout: 0)
    }

    func testCombinedReceiver_withMultiValidReceiver_itSendsToFirstOnly() throws {
        let expectation = self.expectation(description: "receive message")
        let noExpectation = self.expectation(description: "do not receive message")
        noExpectation.isInverted = true

        let receiver = CombinedFeatureMessageReceiver(
            TestReceiver(expectation: expectation),
            TestReceiver(expectation: noExpectation)
        )

        XCTAssertTrue(try receiver.receive(message: .baggage(key: .mockAny(), value: "test"), from: core))
        waitForExpectations(timeout: 0)
    }
}
