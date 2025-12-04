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

class ContextSharingExtensionTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private let queue = DispatchQueue(label: "com.datadog.test.sync")

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
        expectation.expectedFulfillmentCount = 2
        expectation.assertForOverFulfill = false
        var receivedContexts: [SharedContext?] = []

        // When
        CrossPlatformExtension.subscribe { context in
            self.queue.sync {
                receivedContexts.append(context)
            }
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertNotNil(core.get(feature: ContextSharingFeature.self))
        queue.sync {
            XCTAssertEqual(receivedContexts.count, 2, "Should receive at least 2 context updates")
        }
    }

    func testSubscribe_receivesContextUpdates() throws {
        // Given
        let expectation = expectation(description: "subscriber receives context update")
        expectation.expectedFulfillmentCount = 4
        expectation.assertForOverFulfill = false

        var receivedContexts: [SharedContext?] = []

        CrossPlatformExtension.subscribe { context in
            self.queue.sync {
                receivedContexts.append(context)
            }
            expectation.fulfill()
        }

        // When
        core.setUserInfo(id: "user-123")
        core.setAccountInfo(id: "account-456")

        // Then
        waitForExpectations(timeout: 5)
        queue.sync {
            XCTAssertGreaterThanOrEqual(receivedContexts.count, 4, "Should receive at least 4 context updates")

            // Verify we eventually get the user and account info
            let lastContext = receivedContexts.last
            XCTAssertEqual(lastContext??.userId, "user-123", "Should have user ID in final context")
            XCTAssertEqual(lastContext??.accountId, "account-456", "Should have account ID in final context")
        }
    }

    func testSubscribe_calledMultipleTimes() throws {
        // Given
        var subscriptionIds = [Int]()

        // When
        CrossPlatformExtension.subscribe { _ in
            self.queue.sync {
                subscriptionIds.append(1)
            }
        }

        CrossPlatformExtension.subscribe { _ in
            self.queue.sync {
                subscriptionIds.append(2)
            }
        }

        // Then
        queue.sync {
            XCTAssertEqual(subscriptionIds, [1, 2])
        }
    }
}
