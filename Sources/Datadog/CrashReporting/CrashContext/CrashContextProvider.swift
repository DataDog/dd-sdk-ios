/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for writing and reading  the `CrashContext`
internal protocol CrashContextProviderType: class {
    /// Returns current `CrashContext` value.
    var currentCrashContext: CrashContext { get }
    /// Notifies on `CrashContext` change.
    var onCrashContextChange: ((CrashContext) -> Void)? { set get }

    /// Updates the `CrashContext` with last `RUMEvent<RUMViewEvent>` information.
    func update(lastRUMViewEvent: RUMEvent<RUMViewEvent>)
}

/// Manages the `CrashContext` reads and writes in a thread-safe manner.
internal class CrashContextProvider: CrashContextProviderType {
    /// Queue for synchronizing `unsafeCrashContext` updates.
    private let queue: DispatchQueue
    /// Unsychronized `CrashContext`. The `queue` must be used to synchronize its mutation.
    private var unsafeCrashContext: CrashContext {
        willSet { onCrashContextChange?(newValue) }
    }

    /// Observes changes to a particular `Value` in the `CrashContext` and manages its updates.
    private struct ContextValueUpdater<Value>: ValueObserver {
        let queue: DispatchQueue
        let update: (Value) -> Void

        func onValueChanged(oldValue: Value, newValue: Value) {
            queue.async { update(newValue) }
        }
    }

    /// Updates `CrashContext` with last `TrackingConsent` information.
    private lazy var trackingConsentUpdater = ContextValueUpdater<TrackingConsent>(queue: queue) { newTrackingConsent in
        self.unsafeCrashContext.lastTrackingConsent = newTrackingConsent
    }

    /// Updates `CrashContext` with last `UserInfo` information.
    private lazy var userInfoUpdater = ContextValueUpdater<UserInfo>(queue: queue) { newUserInfo in
        self.unsafeCrashContext.lastUserInfo = newUserInfo
    }

    // MARK: - Initializer

    init(
        consentProvider: ConsentProvider,
        userInfoProvider: UserInfoProvider
    ) {
        self.queue = DispatchQueue(
            label: "com.datadoghq.crash-context",
            target: .global(qos: .utility)
        )
        // Set initial context
        self.unsafeCrashContext = CrashContext(
            lastTrackingConsent: consentProvider.currentValue,
            lastUserInfo: userInfoProvider.value,
            lastRUMViewEvent: nil,
            lastNetworkConnectionInfo: nil // TODO: RUMM-1049 provide default value
        )

        // Subscribe for context updates
        consentProvider.subscribe(trackingConsentUpdater)
        userInfoProvider.subscribe(userInfoUpdater)
    }

    // MARK: - CrashContextProviderType

    var currentCrashContext: CrashContext {
        queue.sync { unsafeCrashContext }
    }

    var onCrashContextChange: ((CrashContext) -> Void)? = nil

    func update(lastRUMViewEvent: RUMEvent<RUMViewEvent>) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            var context = self.unsafeCrashContext
            context.lastRUMViewEvent = lastRUMViewEvent
            self.unsafeCrashContext = context
        }
    }
}
