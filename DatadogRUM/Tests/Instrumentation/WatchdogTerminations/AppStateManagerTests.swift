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
    func testDeleteAppState() async {
        // Given
        let featureScope = FeatureScopeMock()
        let sut = AppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false
        )

        await sut.storeCurrentAppState()

        let storedState: AppStateInfo? = await featureScope.rumDataStore.value(forKey: .appStateKey)
        XCTAssertNotNil(storedState)

        // When
        await sut.deleteAppState()

        // Then
        let deletedState: AppStateInfo? = await featureScope.rumDataStore.value(forKey: .appStateKey)
        XCTAssertNil(deletedState)
    }

    func testOnInitialStateLoaded_thereIsAPreviousAppState() async {
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

        // Then
        let previousAppState = await appStateManager.fetchAppStateInfo().previous
        XCTAssertEqual(previousAppState?.debugDescription, mockedPreviousState.debugDescription)
    }

    func testUpdateAppState_itUpdatesCorrectly() async {
        // Given
        let dataStore = DataStoreAsyncMock()
        let featureScope = FeatureScopeMock(dataStore: dataStore)
        let initialState = AppStateInfo.mockWith(wasTerminated: false, isActive: true)
        featureScope.rumDataStore.setValue(initialState, forKey: .appStateKey)
        dataStore.flush()

        let appStateManager = AppStateManager(
            featureScope: featureScope,
            processId: .init(),
            syntheticsEnvironment: false
        )

        let previousAppState = await appStateManager.fetchAppStateInfo().previous
        XCTAssertEqual(previousAppState?.wasTerminated, false)
        XCTAssertEqual(previousAppState?.isActive, true)

        // When
        await appStateManager.updateAppState(state: .active)
        dataStore.flush()

        // Then
        let activeState: AppStateInfo? = await featureScope.rumDataStore.value(forKey: .appStateKey)
        XCTAssertTrue(activeState?.isActive == true)

        // When
        await appStateManager.updateAppState(state: .background)
        dataStore.flush()

        // Then
        let backgroundState: AppStateInfo? = await featureScope.rumDataStore.value(forKey: .appStateKey)
        XCTAssertTrue(backgroundState?.isActive == false)
    }
}
