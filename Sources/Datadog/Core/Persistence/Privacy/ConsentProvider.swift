/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol ConsentSubscriber: class {
    func consentChanged(from oldValue: TrackingConsent, to newValue: TrackingConsent)
}

/// Provides the current `TrackingConsent` value and notifies all subscribers on its change.
internal class ConsentProvider {
    private let queue = DispatchQueue(
        label: "com.datadoghq.tracking-consent",
        target: .global(qos: .userInteractive)
    )
    private var subscribers: [ConsentSubscriber] = []

    init(initialConsent: TrackingConsent) {
        self.unsafeCurrentValue = initialConsent
    }

    // MARK: - Consent Value

    /// Unsychronized consent value. Use `self.currentValue` setter & getter.
    private var unsafeCurrentValue: TrackingConsent

    /// The current value of`TrackingConsent`.
    private(set) var currentValue: TrackingConsent {
        get { queue.sync { unsafeCurrentValue } }
        set { queue.async { self.unsafeCurrentValue = newValue } }
    }

    /// Sets the new value of `TrackingConsent` and notifies all subscribers.
    func changeConsent(to newValue: TrackingConsent) {
        let oldValue = currentValue
        currentValue = newValue

        subscribers.forEach { subscriber in
            subscriber.consentChanged(from: oldValue, to: newValue)
        }
    }

    // MARK: - Managing Subscribers

    func subscribe(consentSubscriber: ConsentSubscriber) {
        subscribers.append(consentSubscriber)
    }
}
