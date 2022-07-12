/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// TODO: RUMM-2034 Remove this flag once we have a host application for tests
#if !os(tvOS)

class LaunchTimeReaderTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        setenv("ActivePrewarm", "", 1)
    }

    func testGivenStartedApplication_whenRequestingLaunchTimeAtAnyTime_itReturnsTheSameValue() {
        // Given
        let publisher = LaunchTimeReader()

        // When
        var values: [TimeInterval] = []
        (0..<10).forEach { _ in
            Thread.sleep(forTimeInterval: 0.01)
            var launchTime = LaunchTime(launchTime: .mockRandom(), isActivePrewarm: false)
            publisher.read(to: &launchTime)
            values.append(launchTime.launchTime)
        }

        // Then
        let uniqueValues = Set(values)
        XCTAssertEqual(uniqueValues.count, 1, "All collected `launchTime` values should be the same.")
        XCTAssertGreaterThan(values[0], 0)
    }

    func testThreadSafety() {
        let publisher = LaunchTimeReader()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                {
                    var launchTime: LaunchTime = .mockAny()
                    publisher.read(to: &launchTime)
                }
            ],
            iterations: 100
        )
        // swiftlint:enable opening_brace
    }

    func testIsActivePrewarm_returnsTrue() {
        // Given
        let publisher = LaunchTimeReader()

        // When
        setenv("ActivePrewarm", "1", 1)
        NSClassFromString("AppLaunchHandler")?.load()

        var launchTime = LaunchTime(launchTime: 0, isActivePrewarm: false)
        publisher.read(to: &launchTime)

        // Then
        XCTAssertTrue(launchTime.isActivePrewarm)
    }

    func testIsActivePrewarm_returnsFalse() {
        // Given
        let publisher = LaunchTimeReader()

        // When
        NSClassFromString("AppLaunchHandler")?.load()
        var launchTime = LaunchTime(launchTime: 0, isActivePrewarm: true)
        publisher.read(to: &launchTime)

        // Then
        XCTAssertFalse(launchTime.isActivePrewarm)
    }
}

#endif
