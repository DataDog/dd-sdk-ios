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

    /// The status of the app state manager indicating if it is active or not.
    /// When it is active, it listens to the app state changes and updates the app state in the data store.
    @ReadWriteLock
    var isActive: Bool

    /// The process identifier of the app whose state is being monitored.
    let processId: UUID

    init(featureScope: FeatureScope, processId: UUID) {
        self.featureScope = featureScope
        self.isActive = false
        self.processId = processId
    }

    /// Starts the app state monitoring. Depending on the app state changes, it updates the app state in the data store.
    /// For example, when the app goes to the background, the app state is updated with `isActive = false`.`
    func start() throws {
        DD.logger.debug("Start app state monitoring")
        isActive = true
        try storeCurrentAppState()
    }

    /// Stops the app state monitoring.
    func stop() throws {
        DD.logger.debug("Stop app state monitoring")
        isActive = false
    }

    /// Deletes the app state from the data store.
    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        featureScope.rumDataStore.removeValue(forKey: .watchdogAppStateKey)
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
    private func storeCurrentAppState() throws {
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
                processId: self.processId
            )
            completion(state)
        }
    }
}

extension WatchdogTerminationAppStateManager: FeatureMessageReceiver {
    /// Receives the feature message and updates the app state based on the context message.
    /// It relies on `ApplicationStatePublisher` context message to update the app state.
    /// Other messages are ignored.
    /// - Parameters:
    ///   - message: The feature message.
    ///   - core: The core instance.
    /// - Returns: Always `false`, because it doesn't block the message propagation.
    func receive(message: DatadogInternal.FeatureMessage, from core: any DatadogInternal.DatadogCoreProtocol) -> Bool {
        guard isActive else {
            return false
        }

        switch message {
        case .baggage, .webview, .telemetry:
            break
        case .context(let context):
            let state = context.applicationStateHistory.currentSnapshot.state

            // the message received on multiple times whenever there is change in context
            // but it may not be the application state, hence we guard against the same state
            guard state != lastAppState else {
                return false
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
        return false
    }
}
