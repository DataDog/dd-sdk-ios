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

    override func tearDown() async throws {
        CrossPlatformExtension.unsubscribeFromSharedContext()
        try? await core.flushAndTearDown()
        CoreRegistry.unregisterDefault()
        core = nil
    }

    @MainActor
    func testSubscribe_registersFeature() throws {
        let expectation = expectation(description: "subscriber is called")
        expectation.assertForOverFulfill = false

        CrossPlatformExtension.subscribe { context in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertNotNil(core.get(feature: ContextSharingFeature.self))
    }

    @MainActor
    func testSubscribe_receivesContextUpdates() throws {
        let expectation = expectation(description: "subscriber receives context update")
        expectation.assertForOverFulfill = false
        nonisolated(unsafe) var lastContext: SharedContext?

        CrossPlatformExtension.subscribe { context in
            if context?.userId != nil && context?.accountId != nil {
                lastContext = context
                expectation.fulfill()
            }
        }

        core.setUserInfo(id: "user-123")
        core.setAccountInfo(id: "account-456")

        waitForExpectations(timeout: 1)

        XCTAssertEqual(lastContext?.userId, "user-123", "Should have user ID in final context")
        XCTAssertEqual(lastContext?.accountId, "account-456", "Should have account ID in final context")
    }

    @MainActor
    func testSubscribe_calledMultipleTimes() throws {
        let expectation1 = expectation(description: "first subscriber receives context update")
        let expectation2 = expectation(description: "second subscriber receives context update")
        expectation2.assertForOverFulfill = false

        CrossPlatformExtension.subscribe { _ in
            expectation1.fulfill()
        }

        CrossPlatformExtension.subscribe { _ in
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1)
    }
}
