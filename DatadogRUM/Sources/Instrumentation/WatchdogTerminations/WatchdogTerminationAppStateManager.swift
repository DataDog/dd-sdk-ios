/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
    private let didBecomeActiveNotificationName = UIApplication.didBecomeActiveNotification
    private let willResignActiveNotificationName = UIApplication.willResignActiveNotification
    private let willTerminateNotificationName = UIApplication.willTerminateNotification
#else
    private let didBecomeActiveNotificationName = NSApplicationDidBecomeActiveNotification
    private let willResignActiveNotificationName = NSApplicationWillResignActiveNotification
    private let willTerminateNotificationName = NSApplicationWillTerminateNotification
#endif

/// Manages the app state changes observed during application lifecycle events such as application start, resume and termination.
internal final class WatchdogTerminationAppStateManager {
    static let appStateKey = "app-state"

    let notificationCenter: NotificationCenter
    var vendorIdProvider: VendorIdProvider
    let dataStore: CodableDataStore
    let featureScope: FeatureScope
    let sysctl: SysctlProviding

    init(
        dataStore: CodableDataStore,
        vendorIdProvider: VendorIdProvider,
        featureScope: FeatureScope,
        sysctl: SysctlProviding,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dataStore = dataStore
        self.notificationCenter = notificationCenter
        self.vendorIdProvider = vendorIdProvider
        self.featureScope = featureScope
        self.sysctl = sysctl
    }

    func addObservers() {
        notificationCenter.addObserver(self, selector: #selector(didBecomeActive), name: didBecomeActiveNotificationName, object: nil)
        notificationCenter.addObserver(self, selector: #selector(willResignActive), name: willResignActiveNotificationName, object: nil)
        notificationCenter.addObserver(self, selector: #selector(willTerminate), name: willTerminateNotificationName, object: nil)
    }

    func removeObservers() {
        notificationCenter.removeObserver(self, name: didBecomeActiveNotificationName, object: nil)
        notificationCenter.removeObserver(self, name: willResignActiveNotificationName, object: nil)
        notificationCenter.removeObserver(self, name: willTerminateNotificationName, object: nil)
    }

    @objc
    func didBecomeActive() throws {
        updateAppState { state in
            state?.isActive = true
        }
    }

    @objc
    func willResignActive() throws {
        updateAppState { state in
            state?.isActive = false
        }
    }

    @objc
    func willTerminate() {
        updateAppState { state in
            state?.wasTerminated = true
        }
    }

    func start() throws {
        try storeCurrentAppState()
        addObservers()
    }

    func stop() throws {
        removeObservers()
    }

    func updateAppState(block: @escaping (inout WatchdogTerminationAppState?) -> Void) {
        dataStore.value(forKey: Self.appStateKey) { (appState: WatchdogTerminationAppState?) in
            var appState = appState
            block(&appState)
            DD.logger.debug("Updating app state in data store")
            self.dataStore.set(appState, forKey: Self.appStateKey)
        }
    }

    func storeCurrentAppState() throws {
        try currentAppState { [self] appState in
            dataStore.set(appState, forKey: Self.appStateKey)
        }
    }

    func deleteAppState() {
        DD.logger.debug("Deleting app state from data store")
        dataStore.removeValue(forKey: Self.appStateKey)
    }

    func readAppState(completion: @escaping (WatchdogTerminationAppState?) -> Void) {
        dataStore.value(forKey: Self.appStateKey) { (state: WatchdogTerminationAppState?) in
            DD.logger.debug("Reading app state from data store.")
            completion(state)
        }
    }

    func currentAppState(completion: @escaping (WatchdogTerminationAppState) -> Void) throws {
        let systemBootTime = try sysctl.systemBootTime()
        let osVersion = try sysctl.osVersion()
        let isDebugging = sysctl.isDebugging()
        let vendorId = vendorIdProvider.vendorId
        featureScope.context { context in
            let state: WatchdogTerminationAppState = .init(
                appVersion: context.version,
                osVersion: osVersion,
                systemBootTime: systemBootTime,
                isDebugging: isDebugging,
                wasTerminated: false,
                isActive: true,
                vendorId: vendorId
            )
            completion(state)
        }
    }
}
