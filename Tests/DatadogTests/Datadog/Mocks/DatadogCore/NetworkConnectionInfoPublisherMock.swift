/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal final class NetworkConnectionInfoPublisherMock: NetworkConnectionInfoPublisher {
    private var receiver: ContextValueReceiver<NetworkConnectionInfo?>?

    var networkConnectionInfo: NetworkConnectionInfo? {
        didSet { receiver?(networkConnectionInfo) }
    }

    func set(queue: DispatchQueue) -> Self {
        // no-op
        return self
    }

    func read(_ receiver: (NetworkConnectionInfo?) -> Void) {
        receiver(networkConnectionInfo)
    }

    func publish(to receiver: @escaping ContextValueReceiver<NetworkConnectionInfo?>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}

extension NetworkConnectionInfoPublisher {
    static func mockAny() -> AnyNetworkConnectionInfoPublisher {
        NetworkConnectionInfoPublisherMock().eraseToAnyPublisher()
    }
}
