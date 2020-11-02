/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LaunchTimeProviderTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testGivenAppBeingStarted_whenDidBecomeActiveNotificationIsSent_itProvidesLaunchTime() throws {
        // Given
        let provider = LaunchTimeProvider(notificationCenter: notificationCenter)
        XCTAssertNil(provider.launchTime, "No `.launchTime` should be provided until notification is sent")

        // When
        notificationCenter.post(Notification(name: UIApplication.didBecomeActiveNotification))

        // Then
        let launchTime = try XCTUnwrap(provider.launchTime)
        XCTAssertGreaterThan(launchTime, 0)
    }

    func testGivenStartedApplication_whenRequestingLaunchTimeAtAnyTime_itReturnsTheSameValue() {
        // Given
        let provider = LaunchTimeProvider(notificationCenter: notificationCenter)
        notificationCenter.post(Notification(name: UIApplication.didBecomeActiveNotification))

        // When
        var values: [TimeInterval] = []
        (0..<10).forEach { _ in
            Thread.sleep(forTimeInterval: 0.01)
            values.append(provider.launchTime!)
        }

        // Then
        let uniqueValues = Set(values)
        XCTAssertEqual(uniqueValues.count, 1, "All collected `launchTime` values should be the same.")
    }

    func testThreadSafety() {
        let notificationCentersAndProviders: [
            (notificationCenter: NotificationCenter, provider: LaunchTimeProvider)
        ] = (0..<10)
            .map { _ in
                let notificationCenter = NotificationCenter()
                return (
                    notificationCenter: notificationCenter,
                    provider: LaunchTimeProvider(notificationCenter: notificationCenter)
                )
            }

        // swiftlint:disable opening_brace
        notificationCentersAndProviders.forEach { notificationCenter, provider in
            callConcurrently(
                closures: [
                    { _ = provider.launchTime },
                    { notificationCenter.post(Notification(name: UIApplication.didBecomeActiveNotification)) }
                ],
                iterations: 1
            )
        }
        // swiftlint:enable opening_brace
    }
}
