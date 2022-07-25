/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LaunchTimeReaderTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        setenv("ActivePrewarm", "", 1)
    }

    func testGivenStartedApplication_whenRequestingLaunchTimeAtAnyTime_itReturnsTheSameValue() throws {
        // Given
        let reader = LaunchTimeReader()

        // When
        var values: [TimeInterval] = []
        try (0..<10).forEach { _ in
            Thread.sleep(forTimeInterval: 0.01)
            var launchTime: LaunchTime? = .init(launchTime: .mockRandom(), isActivePrewarm: false)
            reader.read(to: &launchTime)
            try values.append(XCTUnwrap(launchTime?.launchTime))
        }

        // Then
        let uniqueValues = Set(values)
        XCTAssertEqual(uniqueValues.count, 1, "All collected `launchTime` values should be the same.")
        XCTAssertGreaterThan(values[0], 0)
    }

    func testThreadSafety() {
        let reader = LaunchTimeReader()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                {
                    var launchTime: LaunchTime? = .mockAny()
                    reader.read(to: &launchTime)
                }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }

    func testIsActivePrewarm_returnsTrue() {
        // Given
        let reader = LaunchTimeReader()

        // When
        setenv("ActivePrewarm", "1", 1)
        NSClassFromString("AppLaunchHandler")?.load()

        var launchTime: LaunchTime? = .init(launchTime: 0, isActivePrewarm: false)
        reader.read(to: &launchTime)

        // Then
        XCTAssertTrue(launchTime?.isActivePrewarm ?? false)
    }

    func testIsActivePrewarm_returnsFalse() {
        // Given
        let reader = LaunchTimeReader()

        // When
        NSClassFromString("AppLaunchHandler")?.load()
        var launchTime: LaunchTime? = .init(launchTime: 0, isActivePrewarm: true)
        reader.read(to: &launchTime)

        // Then
        XCTAssertFalse(launchTime?.isActivePrewarm ?? true)
    }
}
