/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationAppStateManagerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var sut: WatchdogTerminationAppStateManager!
    var featureScope: FeatureScopeMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        featureScope = FeatureScopeMock()
        sut = WatchdogTerminationAppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false
        )
    }

    func testUpdateAppState_SetsIsActive() throws {
        try sut.storeCurrentAppState()

        let isActiveExpectation = expectation(description: "isActive is set to true")

        // app state changes
        sut.updateAppState(state: .active)
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertTrue(appState?.isActive == true)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 1)

        let isBackgroundedExpectation = expectation(description: "isActive is set to false")

        // app state changes again
        sut.updateAppState(state: .background)
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertTrue(appState?.isActive == false)
            isBackgroundedExpectation.fulfill()
        }

        wait(for: [isBackgroundedExpectation], timeout: 1)
    }

    func testDeleteAppState() throws {
        try sut.storeCurrentAppState()

        let isActiveExpectation = expectation(description: "isActive is set")
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertNotNil(appState)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 1)

        let deleteExpectation = expectation(description: "isActive is set to false")
        sut.deleteAppState()
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            XCTAssertNil(appState)
            deleteExpectation.fulfill()
        }

        wait(for: [deleteExpectation], timeout: 1)
    }
}
