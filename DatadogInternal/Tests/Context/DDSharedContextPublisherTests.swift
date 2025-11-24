/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
@testable import DatadogInternal

class DDSharedContextPublisherTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testInitialContextIsNil() {
        // Given
        let publisher = DDSharedContextPublisher()

        // Then
        XCTAssertNil(publisher.context)
    }

    func testReceiveContextMessage_updatesContext() {
        // Given
        let publisher = DDSharedContextPublisher()
        let datadogContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-123", name: "John", email: "john@example.com", extraInfo: [:]),
            accountInfo: AccountInfo(id: "account-456", name: "Acme Corp", extraInfo: [:])
        )

        // When
        let result = publisher.receive(message: .context(datadogContext), from: core)

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(publisher.context)
        XCTAssertEqual(publisher.context?.userId, "user-123")
        XCTAssertEqual(publisher.context?.accountId, "account-456")
    }

    func testReceiveContextMessage_withNilUserInfo_updatesContext() {
        // Given
        let publisher = DDSharedContextPublisher()
        let datadogContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: nil, name: nil, email: nil, extraInfo: [:]),
            accountInfo: nil
        )

        // When
        let result = publisher.receive(message: .context(datadogContext), from: core)

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(publisher.context)
        XCTAssertNil(publisher.context?.userId)
        XCTAssertNil(publisher.context?.accountId)
    }

    func testReceiveContextMessage_triggersCallback() {
        // Given
        let expectation = expectation(description: "callback is triggered")
        var capturedContext: DDSharedContext?

        let publisher = DDSharedContextPublisher { sharedContext in
            capturedContext = sharedContext
            expectation.fulfill()
        }

        let datadogContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-789", name: nil, email: nil, extraInfo: [:]),
            accountInfo: AccountInfo(id: "account-123", name: nil, extraInfo: [:])
        )

        // When
        let result = publisher.receive(message: .context(datadogContext), from: core)

        // Then
        XCTAssertTrue(result)
        waitForExpectations(timeout: 0)
        XCTAssertNotNil(capturedContext)
        XCTAssertEqual(capturedContext?.userId, "user-789")
        XCTAssertEqual(capturedContext?.accountId, "account-123")
    }

    func testReceiveContextMessage_withoutCallback_doesNotCrash() {
        // Given
        let publisher = DDSharedContextPublisher(onContextUpdate: nil)
        let datadogContext = DatadogContext.mockRandom()

        // When
        let result = publisher.receive(message: .context(datadogContext), from: core)

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(publisher.context)
    }

    func testReceiveNonContextMessage_returnsFalse() {
        // Given
        let publisher = DDSharedContextPublisher()

        // When
        let result = publisher.receive(message: .payload("test"), from: core)

        // Then
        XCTAssertFalse(result)
        XCTAssertNil(publisher.context)
    }

    func testReceiveMultipleContextMessages_updatesContext() {
        // Given
        let publisher = DDSharedContextPublisher()

        let firstContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-1", name: nil, email: nil, extraInfo: [:]),
            accountInfo: nil
        )

        let secondContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-2", name: nil, email: nil, extraInfo: [:]),
            accountInfo: AccountInfo(id: "account-2", name: nil, extraInfo: [:])
        )

        // When
        let firstResult = publisher.receive(message: .context(firstContext), from: core)
        XCTAssertTrue(firstResult)
        XCTAssertEqual(publisher.context?.userId, "user-1")
        XCTAssertNil(publisher.context?.accountId)

        let secondResult = publisher.receive(message: .context(secondContext), from: core)

        // Then
        XCTAssertTrue(secondResult)
        XCTAssertEqual(publisher.context?.userId, "user-2")
        XCTAssertEqual(publisher.context?.accountId, "account-2")
    }

    func testReceiveContextMessage_callbackInvokedMultipleTimes() {
        // Given
        let expectation = expectation(description: "callback is triggered twice")
        expectation.expectedFulfillmentCount = 2

        var callbackCount = 0
        var capturedContexts: [DDSharedContext] = []

        let publisher = DDSharedContextPublisher { sharedContext in
            callbackCount += 1
            capturedContexts.append(sharedContext)
            expectation.fulfill()
        }

        let firstContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-first", name: nil, email: nil, extraInfo: [:]),
            accountInfo: nil
        )

        let secondContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-second", name: nil, email: nil, extraInfo: [:]),
            accountInfo: nil
        )

        // When
        _ = publisher.receive(message: .context(firstContext), from: core)
        _ = publisher.receive(message: .context(secondContext), from: core)

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(callbackCount, 2)
        XCTAssertEqual(capturedContexts.count, 2)
        XCTAssertEqual(capturedContexts[0].userId, "user-first")
        XCTAssertEqual(capturedContexts[1].userId, "user-second")
    }

    func testThreadSafety_concurrentReads() {
        // Given
        let publisher = DDSharedContextPublisher()
        let datadogContext = DatadogContext.mockWith(
            userInfo: UserInfo(id: "user-concurrent", name: nil, email: nil, extraInfo: [:]),
            accountInfo: nil
        )
        _ = publisher.receive(message: .context(datadogContext), from: core)

        let expectation = self.expectation(description: "concurrent reads complete")
        expectation.expectedFulfillmentCount = 100

        // When
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = publisher.context
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
    }

    func testThreadSafety_concurrentWrites() {
        // Given
        let publisher = DDSharedContextPublisher()
        let expectation = self.expectation(description: "concurrent writes complete")
        expectation.expectedFulfillmentCount = 100

        // When
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let datadogContext = DatadogContext.mockWith(
                userInfo: UserInfo(id: "user-\(index)", name: nil, email: nil, extraInfo: [:]),
                accountInfo: nil
            )
            _ = publisher.receive(message: .context(datadogContext), from: core)
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertNotNil(publisher.context)
    }

    func testThreadSafety_concurrentReadsAndWrites() {
        // Given
        let publisher = DDSharedContextPublisher()
        let expectation = self.expectation(description: "concurrent reads and writes complete")
        expectation.expectedFulfillmentCount = 200

        // When
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let datadogContext = DatadogContext.mockWith(
                userInfo: UserInfo(id: "user-\(index)", name: nil, email: nil, extraInfo: [:]),
                accountInfo: nil
            )
            _ = publisher.receive(message: .context(datadogContext), from: core)
            expectation.fulfill()
        }

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = publisher.context
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertNotNil(publisher.context)
    }
}
