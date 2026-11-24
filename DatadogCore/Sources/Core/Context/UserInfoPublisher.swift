/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Publishes the current `UserInfo` value to receiver.
internal final class UserInfoPublisher: ContextValuePublisher {
    let initialValue: UserInfo? = .empty

    @ReadWriteLock
    private var receiver: ContextValueReceiver<UserInfo>?

    @ReadWriteLock
    private var value: UserInfo = .empty

    var current: UserInfo {
        get { value }
        set { update { $0 = newValue } }
    }

    /// Atomically reads, modifies and publishes the current user info.
    ///
    /// The value is published while holding the lock, so concurrent updates reach the receiver in order.
    func update(_ block: (inout UserInfo) -> Void) {
        _value.mutate { value in
            block(&value)
            receiver?(value)
        }
    }

    func publish(to receiver: @escaping ContextValueReceiver<UserInfo?>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
