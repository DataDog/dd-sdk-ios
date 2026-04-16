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
    func testSubscribe_receivesContextUpdates() throws {
        // Given
        let core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        @ReadWriteLock
        var lastContext: SharedContext?
        CrossPlatformExtension.subscribe { context in
            lastContext = context
        }

        // When
        core.setUserInfo(id: "user-123")
        core.setAccountInfo(id: "account-456")
        try core.flushAndTearDown()

        // Then
        // Verify we eventually get the user and account info
        XCTAssertEqual(lastContext?.userId, "user-123", "Should have user ID in final context")
        XCTAssertEqual(lastContext?.accountId, "account-456", "Should have account ID in final context")
    }
}
