/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Publishes the current `AccountInfo` value to receiver.
internal final class AccountInfoPublisher: ContextValuePublisher {
    let initialValue: AccountInfo? = nil

    @ReadWriteLock
    private var receiver: ContextValueReceiver<AccountInfo?>?

    @ReadWriteLock
    private var value: AccountInfo? = nil

    var current: AccountInfo? {
        get { value }
        set {
            update {
                $0 = newValue
                return true
            }
        }
    }

    /// Atomically reads and modifies the current account info, and publishes it if `block` returns `true`.
    ///
    /// The value is published while holding the lock, so concurrent updates reach the receiver in order.
    ///
    /// - Parameter block: Modifies the account info and returns whether it should be published.
    /// - Returns: Whether the account info was published.
    @discardableResult
    func update(_ block: (inout AccountInfo?) -> Bool) -> Bool {
        var published = false
        _value.mutate { value in
            guard block(&value) else {
                return
            }
            receiver?(value)
            published = true
        }
        return published
    }

    func publish(to receiver: @escaping ContextValueReceiver<AccountInfo?>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
