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

    private var receiver: ContextValueReceiver<Value>?
    private var revision: UInt64 = 0

    var consent: TrackingConsent {
        didSet {
            revision &+= 1
            receiver?(Value(consent: consent, revision: revision))
        }
    }

    init(consent: TrackingConsent) {
        self.initialValue = Value(consent: consent, revision: 0)
        self.consent = consent
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
