/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LaunchTimeProviderTests: XCTestCase {
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
}
