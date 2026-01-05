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

class CrossPlatformExtensionTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CrossPlatformExtension.unsubscribeFromSharedContext()
        try? core.flushAndTearDown()
        CoreRegistry.unregisterDefault()
        core = nil
        super.tearDown()
    }

    func testSubscribe_registersFeature() throws {
        // Given
        let expectation = expectation(description: "subscriber is called")
        expectation.assertForOverFulfill = false

        // When
        CrossPlatformExtension.subscribe { context in
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertNotNil(core.get(feature: ContextSharingFeature.self))
    }

    func testSubscribe_receivesContextUpdates() throws {
        // Given
        let expectation = expectation(description: "subscriber receives context update")
        expectation.assertForOverFulfill = false
        var lastContext: SharedContext?

        CrossPlatformExtension.subscribe { context in
            if context?.userId != nil && context?.accountId != nil {
                expectation.fulfill()
                lastContext = context
            }
        }

        // When
        core.setUserInfo(id: "user-123")
        core.setAccountInfo(id: "account-456")

        // Then
        waitForExpectations(timeout: 1)

        // Verify we eventually get the user and account info
        XCTAssertEqual(lastContext?.userId, "user-123", "Should have user ID in final context")
        XCTAssertEqual(lastContext?.accountId, "account-456", "Should have account ID in final context")
    }

    func testSubscribe_calledMultipleTimes() throws {
        // Given
        let expectation1 = expectation(description: "first subscriber receives context update")
        let expectation2 = expectation(description: "second subscriber receives context update")
        expectation2.assertForOverFulfill = false

        // When
        CrossPlatformExtension.subscribe { _ in
            expectation1.fulfill()
        }

        CrossPlatformExtension.subscribe { _ in
            expectation2.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
    }
}
