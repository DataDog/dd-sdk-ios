/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class LaunchTimePublisherTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        setenv("ActivePrewarm", "", 1)
    }

    func testGivenStartedApplication_itHasLaunchDate() throws {
        // Given
        let publisher = LaunchTimePublisher()

        // When
        let launchTime = publisher.initialValue

        // Then
        XCTAssertNotNil(launchTime?.launchDate)
    }

    func testThreadSafety() {
        let handler = __dd_private_AppLaunchHandler.shared

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = handler.launchTime },
                { _ = handler.launchDate },
                { _ = handler.isActivePrewarm },
                { handler.setApplicationDidBecomeActiveCallback { _ in } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }

    func testIsActivePrewarm_returnsTrue() {
        // Given
        setenv("ActivePrewarm", "1", 1)
        NSClassFromString("__dd_private_AppLaunchHandler")?.load()

        // When
        let publisher = LaunchTimePublisher()

        // Then
        XCTAssertTrue(publisher.initialValue?.isActivePrewarm ?? false)
    }

    func testIsActivePrewarm_returnsFalse() {
        // Given
        NSClassFromString("__dd_private_AppLaunchHandler")?.load()

        // When
        let publisher = LaunchTimePublisher()

        // Then
        XCTAssertFalse(publisher.initialValue?.isActivePrewarm ?? true)
    }
}
