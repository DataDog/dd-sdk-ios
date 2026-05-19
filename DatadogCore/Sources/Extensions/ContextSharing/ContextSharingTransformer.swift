/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ContextSharingTransformer: BusMessageReceiver, ContextValuePublisher {
    @ReadWriteLock
    private var sharedContext: SharedContext? = nil
    @ReadWriteLock
    private var receiver: ContextValueReceiver<SharedContext?>? = nil

    func receive(message context: DatadogContext, from core: DatadogCoreProtocol) {
        let newContext = SharedContext(datadogContext: context)
        sharedContext = newContext
        receiver?(newContext)
    }

    // MARK: - ContextValuePublisher

    var initialValue: SharedContext? = nil

    func publish(to receiver: @escaping ContextValueReceiver<SharedContext?>) {
        self.receiver = receiver
        receiver(sharedContext)
    }

    func cancel() {
        receiver = nil
    }
}
