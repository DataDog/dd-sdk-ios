/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Publishes the current `UserInfo` value to receiver.
internal final class UserInfoPublisher: ContextValuePublisher {
    let initialValue: UserInfo? = .empty

    private var receiver: ContextValueReceiver<UserInfo>?

    var current: UserInfo = .empty {
        didSet { receiver?(current) }
    }

    func publish(to receiver: @escaping ContextValueReceiver<UserInfo?>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
