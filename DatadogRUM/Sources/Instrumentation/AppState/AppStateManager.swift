/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol AppStateManaging {
    /// Deletes the app state from the data store.
    func deleteAppState()
    /// Updates the app state based on the given application state.
    func updateAppState(state: AppState)
    /// Returns the previous app state via `completion` callback.
    func previousAppStateInfo(completion: @escaping (AppStateInfo?) -> Void)
    /// Builds the current app state.
    func currentAppStateInfo(completion: @escaping (AppStateInfo) -> Void)
}

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal final class AppStateManager: AppStateManaging {
    private static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.app-state-manager",
        qos: .utility
    )

    private let featureScope: FeatureScope
    private let initialStateGroup = DispatchGroup()
    private let initialStateQueue: DispatchQueue

    /// The last app state observed during application lifecycle events.
    @ReadWriteLock
    private var lastAppState: AppState?

    /// The app state information of the last application run.
    @ReadWriteLock
    private var previousAppStateInfo: AppStateInfo?

    /// The process identifier of the app whose state is being monitored.
    let processId: UUID

    /// Returns true, if the app is running in a synthetic environment.
    let syntheticsEnvironment: Bool

    init(
        featureScope: FeatureScope,
        processId: UUID,
        syntheticsEnvironment: Bool,
        queue: DispatchQueue = AppStateManager.defaultQueue
    ) {
        self.featureScope = featureScope
        self.processId = processId
        self.syntheticsEnvironment = syntheticsEnvironment
        self.initialStateQueue = queue

        start()
    }

    private func start() {
        initialStateGroup.enter()
        self.readAppState { [weak self] in
            self?.previousAppStateInfo = $0
            self?.storeCurrentAppState()
            self?.initialStateGroup.leave()
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
            updateAppState { stateInfo in
                stateInfo?.isActive = true
            }
        case .inactive, .background:
            updateAppState { stateInfo in
                stateInfo?.isActive = false
            }
        case .terminated:
            updateAppState { stateInfo in
                stateInfo?.wasTerminated = true
            }
        }
        lastAppState = state
    }

    /// Updates the app state in the data store with the given block.
    /// - Parameter block: The block to update the app state.
    private func updateAppState(block: @escaping (inout AppStateInfo?) -> Void) {
        onInitialStateLoaded { [weak self] in
            self?.featureScope.rumDataStore.value(forKey: .appStateKey) { (appState: AppStateInfo?) in
                var appState = appState
                block(&appState)
                DD.logger.debug("Updating app state in data store")
                self?.featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
            }
        }
    }

    /// Returns the previous app state via `completion` block.
    /// - Parameter completion: The completion block called with the previous app state.
    func previousAppStateInfo(completion: @escaping (AppStateInfo?) -> Void) {
        onInitialStateLoaded { [weak self] in
            completion(self?.previousAppStateInfo)
        }
    }

    /// Builds the current app state asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    func currentAppStateInfo(completion: @escaping (AppStateInfo) -> Void) {
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
    func storeCurrentAppState() {
        currentAppStateInfo { [self] appState in
            featureScope.rumDataStore.setValue(appState, forKey: .appStateKey)
        }
    }

    /// Reads the app state from the data store asynchronously.
    /// - Parameter completion: The completion block called with the app state.
    func readAppState(completion: @escaping (AppStateInfo?) -> Void) {
        featureScope.rumDataStore.value(forKey: .appStateKey) { (state: AppStateInfo?) in
            DD.logger.debug("Reading app state from data store.")
            completion(state)
        }
    }

    /// Runs `completion` once initial state completes.
    private func onInitialStateLoaded(_ completion: @escaping () -> Void) {
        initialStateGroup.notify(queue: initialStateQueue, execute: completion)
    }
}
