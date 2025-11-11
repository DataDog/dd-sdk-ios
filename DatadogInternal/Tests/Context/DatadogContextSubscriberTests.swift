/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(objc)
import DatadogInternal

final class DatadogContextSubscriberTests: XCTestCase {
    // MARK: - Basic Functionality

    func testItReceivesContextUpdate() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let mockContext: DatadogContext = .mockAny()
        _ = PassthroughCoreMock(context: mockContext, messageReceiver: subscriber)

        // Then
        XCTAssertEqual(subscriber.context?.service, mockContext.service)
        XCTAssertEqual(subscriber.context?.env, mockContext.env)
        XCTAssertEqual(subscriber.context?.version, mockContext.version)
    }

    func testItIgnoresNonContextMessages() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let core = NOPDatadogCore()

        // When
        let result = subscriber.receive(message: .payload("test"), from: core)

        // Then
        XCTAssertFalse(result)
        XCTAssertNil(subscriber.context)
    }

    func testItReturnsSuccessForContextMessages() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()

        // When
        let result = subscriber.receive(message: .context(mockContext), from: core)

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(subscriber.context)
    }

    // MARK: - Callback Tests

    func testItInvokesCallbackOnContextUpdate() {
        // Given
        let expectation = self.expectation(description: "callback invoked")
        var receivedContext: DatadogContext?

        let subscriber = DatadogContextSubscriber { context in
            receivedContext = context
            expectation.fulfill()
        }

        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()

        // When
        subscriber.receive(message: .context(mockContext), from: core)

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedContext?.service, mockContext.service)
        XCTAssertEqual(receivedContext?.env, mockContext.env)
    }

    func testItAllowsSettingCallbackAfterInitialization() {
        // Given
        let expectation = self.expectation(description: "callback invoked")
        let subscriber = DatadogContextSubscriber()
        var receivedContext: DatadogContext?

        // When
        subscriber.setOnContextUpdate { context in
            receivedContext = context
            expectation.fulfill()
        }

        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()
        subscriber.receive(message: .context(mockContext), from: core)

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedContext?.service, mockContext.service)
    }

    func testItAllowsUpdatingCallback() {
        // Given
        let expectation1 = self.expectation(description: "first callback invoked")
        let expectation2 = self.expectation(description: "second callback invoked")

        var firstCallbackCount = 0
        var secondCallbackCount = 0

        let subscriber = DatadogContextSubscriber { _ in
            firstCallbackCount += 1
            expectation1.fulfill()
        }

        let mockContext1: DatadogContext = .mockAny()
        let mockContext2: DatadogContext = .mockWith(service: "different-service")
        let core = NOPDatadogCore()

        // When - First update with first callback
        subscriber.receive(message: .context(mockContext1), from: core)
        wait(for: [expectation1], timeout: 1.0)

        // Then - Update callback
        subscriber.setOnContextUpdate { _ in
            secondCallbackCount += 1
            expectation2.fulfill()
        }

        // When - Second update with new callback
        subscriber.receive(message: .context(mockContext2), from: core)

        // Then
        wait(for: [expectation2], timeout: 1.0)
        XCTAssertEqual(firstCallbackCount, 1)
        XCTAssertEqual(secondCallbackCount, 1)
    }

    // MARK: - Thread Safety Tests

    func testItHandlesConcurrentReads() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()
        subscriber.receive(message: .context(mockContext), from: core)

        let iterations = 100
        let readExpectation = expectation(description: "concurrent reads completed")
        readExpectation.expectedFulfillmentCount = iterations

        // When - Perform concurrent reads
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = subscriber.context
            readExpectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 2.0)
    }

    func testItHandlesConcurrentWrites() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let core = NOPDatadogCore()

        let iterations = 100
        let writeExpectation = expectation(description: "concurrent writes completed")
        writeExpectation.expectedFulfillmentCount = iterations

        // When - Perform concurrent writes
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let mockContext: DatadogContext = .mockWith(service: "service-\(index)")
            subscriber.receive(message: .context(mockContext), from: core)
            writeExpectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 2.0)
        XCTAssertNotNil(subscriber.context)
    }

    func testItHandlesConcurrentReadsAndWrites() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let core = NOPDatadogCore()

        let iterations = 50
        let readExpectation = expectation(description: "concurrent reads completed")
        readExpectation.expectedFulfillmentCount = 25

        let writeExpectation = expectation(description: "concurrent writes completed")
        writeExpectation.expectedFulfillmentCount = 25

        // When - Perform concurrent reads and writes
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            if index % 2 == 0 {
                // Write
                let mockContext: DatadogContext = .mockWith(service: "service-\(index)")
                subscriber.receive(message: .context(mockContext), from: core)
                writeExpectation.fulfill()
            } else {
                // Read
                _ = subscriber.context
                readExpectation.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 2.0)
        XCTAssertNotNil(subscriber.context)
    }

    func testItHandlesConcurrentCallbackUpdates() {
        // Given
        let subscriber = DatadogContextSubscriber()

        let iterations = 100
        let updateExpectation = expectation(description: "concurrent callback updates completed")
        updateExpectation.expectedFulfillmentCount = iterations

        // When - Perform concurrent callback updates
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            subscriber.setOnContextUpdate { _ in
                // Callback \(index)
            }
            updateExpectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 2.0)
    }

    // MARK: - Context Updates

    func testItUpdatesContextMultipleTimes() {
        // Given
        let subscriber = DatadogContextSubscriber()
        let core = NOPDatadogCore()

        let context1: DatadogContext = .mockWith(service: "service1", env: "env1")
        let context2: DatadogContext = .mockWith(service: "service2", env: "env2")
        let context3: DatadogContext = .mockWith(service: "service3", env: "env3")

        // When
        subscriber.receive(message: .context(context1), from: core)
        XCTAssertEqual(subscriber.context?.service, "service1")

        subscriber.receive(message: .context(context2), from: core)
        XCTAssertEqual(subscriber.context?.service, "service2")

        subscriber.receive(message: .context(context3), from: core)

        // Then
        XCTAssertEqual(subscriber.context?.service, "service3")
        XCTAssertEqual(subscriber.context?.env, "env3")
    }

    // MARK: - Objective-C Wrapper Tests

    func testObjcWrapperReceivesContextUpdate() {
        // Given
        let objcSubscriber = objc_DatadogContextSubscriber()
        let mockContext: DatadogContext = .mockAny()
        let core = PassthroughCoreMock(context: mockContext, messageReceiver: objcSubscriber.messageReceiver)

        // Then
        XCTAssertEqual(objcSubscriber.context?.service, mockContext.service)
        XCTAssertEqual(objcSubscriber.context?.env, mockContext.env)
        XCTAssertEqual(objcSubscriber.context?.swiftContext.service, mockContext.service)
    }

    func testObjcWrapperInvokesCallback() {
        // Given
        let expectation = self.expectation(description: "objc callback invoked")
        var receivedContext: objc_DatadogContext?

        let objcSubscriber = objc_DatadogContextSubscriber { context in
            receivedContext = context
            expectation.fulfill()
        }

        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()

        // When
        _ = objcSubscriber.messageReceiver.receive(message: .context(mockContext), from: core)

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedContext?.service, mockContext.service)
        XCTAssertEqual(receivedContext?.swiftContext.service, mockContext.service)
    }

    func testObjcWrapperAllowsSettingCallback() {
        // Given
        let expectation = self.expectation(description: "objc callback invoked")
        let objcSubscriber = objc_DatadogContextSubscriber()
        var receivedContext: objc_DatadogContext?

        // When
        objcSubscriber.setOnContextUpdate { context in
            receivedContext = context
            expectation.fulfill()
        }

        let mockContext: DatadogContext = .mockAny()
        let core = NOPDatadogCore()
        _ = objcSubscriber.messageReceiver.receive(message: .context(mockContext), from: core)

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedContext?.service, mockContext.service)
        XCTAssertEqual(receivedContext?.swiftContext.service, mockContext.service)
    }

    func testObjcContextConvertsAllProperties() {
        // Given
        let mockContext: DatadogContext = .mockAny()

        // When
        let objcContext = objc_DatadogContext(swiftContext: mockContext)

        // Then
        XCTAssertEqual(objcContext.clientToken, mockContext.clientToken)
        XCTAssertEqual(objcContext.service, mockContext.service)
        XCTAssertEqual(objcContext.env, mockContext.env)
        XCTAssertEqual(objcContext.version, mockContext.version)
        XCTAssertEqual(objcContext.buildNumber, mockContext.buildNumber)
        XCTAssertEqual(objcContext.buildId, mockContext.buildId)
        XCTAssertEqual(objcContext.variant, mockContext.variant)
        XCTAssertEqual(objcContext.source, mockContext.source)
        XCTAssertEqual(objcContext.sdkVersion, mockContext.sdkVersion)
        XCTAssertEqual(objcContext.applicationName, mockContext.applicationName)
        XCTAssertEqual(objcContext.applicationBundleIdentifier, mockContext.applicationBundleIdentifier)
        XCTAssertEqual(objcContext.sdkInitDate, mockContext.sdkInitDate)
        XCTAssertEqual(objcContext.isLowPowerModeEnabled, mockContext.isLowPowerModeEnabled)
        XCTAssertEqual(objcContext.serverTimeOffset, mockContext.serverTimeOffset)
    }
}
