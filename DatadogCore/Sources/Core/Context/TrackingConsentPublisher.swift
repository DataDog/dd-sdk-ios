/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Publishes the user consent to receiver.
internal final class TrackingConsentPublisher: ContextValuePublisher {
    /// A tracking consent and its revision.
    struct Value: Equatable {
        let consent: TrackingConsent
        /// The number of consent changes before this value, so a change back to an earlier consent is still visible.
        let revision: UInt64
    }

    let initialValue: Value

    @ReadWriteLock
    private var receiver: ContextValueReceiver<Value>?

    @ReadWriteLock
    private var value: Value

    var consent: TrackingConsent { value.consent }

    init(consent: TrackingConsent) {
        let value = Value(consent: consent, revision: 0)
        self.initialValue = value
        self.value = value
    }

    /// Atomically changes and publishes the consent, if it differs from the current one.
    ///
    /// The value is published while holding the lock, so concurrent changes reach the receiver in order.
    ///
    /// - Parameters:
    ///   - consent: The new consent.
    ///   - whenChanged: Called after publishing a changed consent, while still holding the lock.
    func update(_ consent: TrackingConsent, whenChanged: () -> Void) {
        _value.mutate { value in
            guard value.consent != consent else {
                return
            }
            value = Value(consent: consent, revision: value.revision &+ 1)
            receiver?(value)
            whenChanged()
        }
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
