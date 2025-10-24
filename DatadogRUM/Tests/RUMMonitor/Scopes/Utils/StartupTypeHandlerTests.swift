/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
@testable import TestUtilities

final class StartupTypeHandlerTests: XCTestCase {
    private var handler: StartupTypeHandler! // swiftlint:disable:this implicitly_unwrapped_optional
    private var appStateManager: AppStateManaging! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        appStateManager = AppStateManagerMock()
        handler = StartupTypeHandler(appStateManager: appStateManager)
    }

    override func tearDown() {
        appStateManager = nil
        handler = nil
        super.tearDown()
    }

    func testFreshInstall_returnsColdStart() {
        // Given
        let currentAppState: AppStateInfo = .mockAny()

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .coldStart)
    }

    func testAppUpdate_returnsColdStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(appVersion: "1.0.0")
        let currentAppState: AppStateInfo = .mockWith(appVersion: "2.0.0")

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .coldStart)
    }

    func testSystemRestart_returnsColdStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(systemBootTime: 1_000_000)
        let currentAppState: AppStateInfo = .mockWith(systemBootTime: 1_100_000)

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .coldStart)
    }

    func testLongInactivity_returnsColdStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(appLaunchTime: 1_000_000)
        let currentAppState: AppStateInfo = .mockWith(appLaunchTime: 1_000_000 + StartupTypeHandler.Constants.maxInactivityDuration + 1)

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .coldStart)
    }

    func testOneWeekInactivity_returnsWarmStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(appLaunchTime: 1_000_000)
        let currentAppState: AppStateInfo = .mockWith(appLaunchTime: 1_000_000 + StartupTypeHandler.Constants.maxInactivityDuration)

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .warmStart)
    }

    func testSimilarAppLaunch_returnsWarmStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(
            appVersion: "1.0.0",
            systemBootTime: 1_000_000,
            appLaunchTime: 1_000_000
        )
        let currentAppState: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            systemBootTime: 1_000_000,
            appLaunchTime: 1_000_000
        )

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .warmStart)
    }

    func testMultipleColdConditions_returnsColdStart() {
        // Given
        (appStateManager as? AppStateManagerMock)?.previousAppStateInfo = .mockWith(
            appVersion: "1.0.0",
            systemBootTime: 1_000_000,
            appLaunchTime: 1_000_000
        )
        let currentAppState: AppStateInfo = .mockWith(
            appVersion: "2.0.0",
            systemBootTime: 1_500_000,
            appLaunchTime: 1_000_000 + StartupTypeHandler.Constants.maxInactivityDuration + 100
        )

        // When
        let result = handler.startupType(currentAppState: currentAppState)

        // Then
        XCTAssertEqual(result, .coldStart)
    }
}
