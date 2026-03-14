/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol AppStateManaging: Sendable {
    /// Updates the app state based on the given application state.
    func updateAppState(state: AppState) async
    /// Fetches both previous and current app state.
    func fetchAppStateInfo() async -> (previous: AppStateInfo?, current: AppStateInfo)
}

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal actor AppStateManager: AppStateManaging {
    private let featureScope: FeatureScope

    /// The last app state observed during application lifecycle events.
    private var lastAppState: AppState?

    /// The app state information of the last application run.
    private var previousAppState: AppStateInfo?

    /// Whether the initial state has been loaded from the data store.
    private var initialized = false

    /// The process identifier of the app whose state is being monitored.
    let processId: UUID

    /// Returns true, if the app is running in a synthetic environment.
    let syntheticsEnvironment: Bool

    init(
        featureScope: FeatureScope,
        processId: UUID,
        syntheticsEnvironment: Bool
    ) {
        self.featureScope = featureScope
        self.processId = processId
        self.syntheticsEnvironment = syntheticsEnvironment
    }

    /// Reads the previous app state from the data store and stores the current one.
    /// Idempotent — only the first call performs the work.
    private func ensureInitialized() async {
        guard !initialized else { return }
        initialized = true
        self.previousAppState = await Self.readAppState(from: featureScope)
        await self.storeCurrentAppState()
    }

    /// Updates the app state based on the given application state.
    ///
    /// For watchdog termination, we are interested in
    /// 1. whether the application was terminated using conventions methods or not.
    /// 2. whether the application was in the foreground or background when it was terminated.
    ///
    /// - Parameter state: The application state.
    func updateAppState(state: AppState) async {
        // this method can be called multiple times for the same state,
        // so we need to make sure we don't update the state multiple times
        guard state != lastAppState else {
            return
        }
        switch state {
        case .active:
            await updateAppStateInStore { $0?.isActive = true }
        case .inactive, .background:
            await updateAppStateInStore { $0?.isActive = false }
        case .terminated:
            await updateAppStateInStore { $0?.wasTerminated = true }
        }
        lastAppState = state
    }

    /// Reads the current app state from the data store, applies the mutation, and writes it back.
    /// - Parameter block: The mutation to apply to the app state.
    private func updateAppStateInStore(block: (inout AppStateInfo?) -> Void) async {
        var appState: AppStateInfo? = await featureScope.rumDataStore.value(forKey: .appStateKey)
        block(&appState)
        DD.logger.debug("Updating app state in data store")
        featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
    }

    /// Returns the previous app state, waiting for initialization if needed.
    private func previousAppStateInfo() async -> AppStateInfo? {
        await ensureInitialized()
        return previousAppState
    }

    /// Builds the current app state asynchronously.
    private func currentAppStateInfo() async -> AppStateInfo {
        guard let context = await featureScope.context() else {
            return AppStateInfo(
                appVersion: "",
                osVersion: "",
                systemBootTime: 0,
                appLaunchTime: 0,
                isDebugging: false,
                wasTerminated: false,
                isActive: true,
                vendorId: nil,
                processId: processId,
                trackingConsent: .pending,
                syntheticsEnvironment: syntheticsEnvironment
            )
        }
        return AppStateInfo(
            appVersion: context.version,
            osVersion: context.os.version,
            systemBootTime: context.device.systemBootTime,
            appLaunchTime: context.launchInfo.processLaunchDate.timeIntervalSince1970,
            isDebugging: context.device.isDebugging,
            wasTerminated: false,
            isActive: true,
            vendorId: context.device.vendorId,
            processId: processId,
            trackingConsent: context.trackingConsent,
            syntheticsEnvironment: syntheticsEnvironment
        )
    }

    /// Builds the current app state and stores it in the data store.
    func storeCurrentAppState() async {
        let appState = await currentAppStateInfo()
        featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
    }

    /// Fetches both previous and current app state.
    func fetchAppStateInfo() async -> (previous: AppStateInfo?, current: AppStateInfo) {
        let previous = await previousAppStateInfo()
        let current = await currentAppStateInfo()
        return (previous, current)
    }

    /// Reads the app state from the data store.
    private static func readAppState(from featureScope: FeatureScope) async -> AppStateInfo? {
        DD.logger.debug("Reading app state from data store.")
        return await featureScope.rumDataStore.value(forKey: .appStateKey)
    }
}

// MARK: - Testing funcs

extension AppStateManager {
    /// Deletes the app state from the data store.
    /// Used for testing only.
    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        featureScope.rumDataStore.removeValue(forKey: .appStateKey)
    }
}
