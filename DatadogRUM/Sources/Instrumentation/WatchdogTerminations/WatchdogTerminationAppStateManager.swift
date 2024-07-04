/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal final class WatchdogTerminationAppStateManager {
    let featureScope: FeatureScope

    /// The last app state observed during application lifecycle events.
    @ReadWriteLock
    var lastAppState: AppState?

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

    /// Deletes the app state from the data store.
    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        featureScope.rumDataStore.removeValue(forKey: .watchdogAppStateKey)
    }

    /// Updates the app state based on the given application state.
    ///
    /// For watchdog termination, we are interested in
    /// 1. whether the application was terminated using conventions methods or not.
    /// 2. whether the application was in the foreground or background when it was terminated.
    ///
    /// - Parameter state: The application state.
    func updateAppState(state: AppState) {
        // this method can be called multiple times for the same state,
        // so we need to make sure we don't update the state multiple times
        guard state != lastAppState else {
            return
        }
        switch state {
        case .active:
            updateAppState { state in
                state?.isActive = true
            }
        case .inactive, .background:
            updateAppState { state in
                state?.isActive = false
            }
        case .terminated:
            updateAppState { state in
                state?.wasTerminated = true
            }
        }
        lastAppState = state
    }

    /// Updates the app state in the data store with the given block.
    /// - Parameter block: The block to update the app state.
    private func updateAppState(block: @escaping (inout WatchdogTerminationAppState?) -> Void) {
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (appState: WatchdogTerminationAppState?) in
            var appState = appState
            block(&appState)
            DD.logger.debug("Updating app state in data store")
            self.featureScope.rumDataStore.setValue(appState, forKey: .watchdogAppStateKey)
        }
    }

    /// Builds the current app state and stores it in the data store.
    func storeCurrentAppState() throws {
        try currentAppState { [self] appState in
            featureScope.rumDataStore.setValue(appState, forKey: .watchdogAppStateKey)
        }
    }

    /// Reads the app state from the data store asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    func readAppState(completion: @escaping (WatchdogTerminationAppState?) -> Void) {
        featureScope.rumDataStore.value(forKey: .watchdogAppStateKey) { (state: WatchdogTerminationAppState?) in
            DD.logger.debug("Reading app state from data store.")
            completion(state)
        }
    }

    /// Builds the current app state asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    func currentAppState(completion: @escaping (WatchdogTerminationAppState) -> Void) throws {
        featureScope.context { context in
            let state: WatchdogTerminationAppState = .init(
                appVersion: context.version,
                osVersion: context.device.osVersion,
                systemBootTime: context.device.systemBootTime,
                isDebugging: context.device.isDebugging,
                wasTerminated: false,
                isActive: true,
                vendorId: context.device.vendorId,
                processId: self.processId,
                trackingConsent: context.trackingConsent,
                syntheticsEnvironment: self.syntheticsEnvironment
            )
            completion(state)
        }
    }
}
