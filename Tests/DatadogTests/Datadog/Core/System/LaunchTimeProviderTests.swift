/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// TODO: RUMM-2034 Remove this flag once we have a host application for tests
#if !os(tvOS)

class LaunchTimeProviderTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        setenv("ActivePrewarm", "", 1)
    }

    func testGivenStartedApplication_whenRequestingLaunchTimeAtAnyTime_itReturnsTheSameValue() {
        // Given
        let provider = LaunchTimeProvider()

        // When
        var values: [TimeInterval] = []
        (0..<10).forEach { _ in
            Thread.sleep(forTimeInterval: 0.01)
            values.append(provider.launchTime)
        }

        // Then
        let uniqueValues = Set(values)
        XCTAssertEqual(uniqueValues.count, 1, "All collected `launchTime` values should be the same.")
        XCTAssertGreaterThan(values[0], TimeInterval(0))
    }

    func testThreadSafety() {
        let provider = LaunchTimeProvider()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [{ _ = provider.launchTime }],
            iterations: 100
        )
        // swiftlint:enable opening_brace
    }

    func testIsActivePrewarm_returnsTrue() {
        // Given
        let provider = LaunchTimeProvider()

        // When
        setenv("ActivePrewarm", "1", 1)
        NSClassFromString("AppLaunchHandler")?.load()

        // Then
        XCTAssertTrue(provider.isActivePrewarm)
    }

    func testIsActivePrewarm_returnsFalse() {
        // Given
        let provider = LaunchTimeProvider()

        // When
        NSClassFromString("AppLaunchHandler")?.load()

        // Then
        XCTAssertFalse(provider.isActivePrewarm)
    }
}

#endif
