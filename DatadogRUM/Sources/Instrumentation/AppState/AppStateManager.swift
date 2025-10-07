/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol AppStateManaging {
    /// The app state information of the last application run.
    var previousAppStateInfo: AppStateInfo? { get }
    /// Deletes the app state from the data store.
    func deleteAppState()
    /// Updates the app state based on the given application state.
    func updateAppState(state: AppState)
    /// Builds the current app state.
    func currentAppStateInfo(completion: @escaping (AppStateInfo) -> Void) throws
    /// Builds the current app state and stores it in the data store.
    func storeCurrentAppState() throws
}

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal final class AppStateManager: AppStateManaging {
    enum ErrorMessage: String {
        case failedToStoreAppState = "Failed to store App State information"
    }

    let featureScope: FeatureScope

    /// The last app state observed during application lifecycle events.
    @ReadWriteLock
    private var lastAppState: AppState?

    /// The app state information of the last application run.
    @ReadWriteLock
    private(set) var previousAppStateInfo: AppStateInfo?

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

        start()
    }

    private func start() {
        self.readAppState { [weak self] in
            self?.previousAppStateInfo = $0

            do {
                try self?.storeCurrentAppState()
            } catch {
                DD.logger.error(ErrorMessage.failedToStoreAppState.rawValue, error: error)
                self?.featureScope.telemetry.error(ErrorMessage.failedToStoreAppState.rawValue, error: error)
            }
        }
    }

    /// Deletes the app state from the data store.
    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        featureScope.rumDataStore.removeValue(forKey: .appStateKey)
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
    private func updateAppState(block: @escaping (inout AppStateInfo?) -> Void) {
        featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
            var appState = appState
            block(&appState)
            DD.logger.debug("Updating app state in data store")
            self.featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
        }
    }

    /// Builds the current app state asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    func currentAppStateInfo(completion: @escaping (AppStateInfo) -> Void) throws {
        featureScope.context { context in
            let state: AppStateInfo = .init(
                appVersion: context.version,
                osVersion: context.os.version,
                systemBootTime: context.device.systemBootTime,
                appLaunchTime: context.launchInfo.processLaunchDate.timeIntervalSince1970,
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

    /// Builds the current app state and stores it in the data store.
    func storeCurrentAppState() throws {
        try currentAppStateInfo { [self] appState in
            featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
        }
    }

    /// Reads the app state from the data store asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    private func readAppState(completion: @escaping (AppStateInfo?) -> Void) {
        featureScope.rumDataStore.value(forKey: .appStateKey) { (state: AppStateInfo?) in
            DD.logger.debug("Reading app state from data store.")
            completion(state)
        }
    }
}
