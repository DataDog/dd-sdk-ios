/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class AppStateManagerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var sut: AppStateManager!
    var featureScope: FeatureScopeMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        featureScope = FeatureScopeMock()
        sut = AppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false
        )
    }

    func testDeleteAppState() {
        sut.storeCurrentAppState()

        let isActiveExpectation = expectation(description: "isActive is set")
        featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
            XCTAssertNotNil(appState)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 1)

        let deleteExpectation = expectation(description: "isActive is set to false")
        sut.deleteAppState()
        featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
            XCTAssertNil(appState)
            deleteExpectation.fulfill()
        }

        wait(for: [deleteExpectation], timeout: 1)
    }

    func testOnInitialStateLoaded_thereIsAPreviousAppState() {
        // Given
        let dataStore = DataStoreAsyncMock()
        let featureScope = FeatureScopeMock(dataStore: dataStore)
        let mockedPreviousState: AppStateInfo = .mockRandom()
        featureScope.rumDataStore.setValue(mockedPreviousState, forKey: .appStateKey)
        dataStore.flush()

        // When
        let appStateManager = AppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false
        )

        let appStateExpectation = expectation(description: "There is a previous app state")
        appStateManager.previousAppStateInfo { previousAppState in
            // Then
            XCTAssertEqual(previousAppState?.debugDescription, mockedPreviousState.debugDescription)
            appStateExpectation.fulfill()
        }

        wait(for: [appStateExpectation], timeout: 0.1)
    }

    func testUpdateAppState_itUpdatesCorrectly() {
        // Given
        let dataStore = DataStoreAsyncMock()
        let featureScope = FeatureScopeMock(dataStore: dataStore)
        let initialStateQueue = DispatchQueue(label: "com.datadoghq.tests.initial-state-update")
        let initialState = AppStateInfo.mockWith(wasTerminated: false, isActive: true)
        featureScope.rumDataStore.setValue(initialState, forKey: .appStateKey)
        dataStore.flush()

        let appStateManager = AppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false,
            queue: initialStateQueue
        )

        let initialStateExpectation = expectation(description: "Initial state is loaded")
        appStateManager.previousAppStateInfo { previousAppState in
            XCTAssertEqual(previousAppState?.wasTerminated, false)
            XCTAssertEqual(previousAppState?.isActive, true)
            initialStateExpectation.fulfill()
        }
        wait(for: [initialStateExpectation], timeout: 0.1)

        // When
        appStateManager.updateAppState(state: .active)
        initialStateQueue.sync {}
        dataStore.flush()

        // Then
        let isActiveExpectation = expectation(description: "isActive is set to true")
        featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
            XCTAssertTrue(appState?.isActive == true)
            isActiveExpectation.fulfill()
        }
        wait(for: [isActiveExpectation], timeout: 0.1)

        // When
        appStateManager.updateAppState(state: .background)
        initialStateQueue.sync {}
        dataStore.flush()

        // Then
        let isBackgroundedExpectation = expectation(description: "isActive is set to false")
        featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
            XCTAssertTrue(appState?.isActive == false)
            isBackgroundedExpectation.fulfill()
        }

        wait(for: [isBackgroundedExpectation], timeout: 0.1)
    }
}
