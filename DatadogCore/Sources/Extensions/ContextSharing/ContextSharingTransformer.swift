/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ContextSharingTransformer: FeatureMessageReceiver {
    @ReadWriteLock
    private var sharedContext: SharedContext? = nil
    @ReadWriteLock
    private var receiver: (@Sendable (SharedContext?) -> Void)? = nil

    // MARK: - FeatureMessageReceiver

    func receive(message: FeatureMessage) {
        switch message {
        case .context(let context):
            let newContext = SharedContext(datadogContext: context)
            sharedContext = newContext
            receiver?(newContext)
        default:
            break
        }
    }

    // MARK: - Shared Context Updates

    func publish(to receiver: @escaping @Sendable (SharedContext?) -> Void) {
        self.receiver = receiver
        receiver(sharedContext)
    }

    func cancel() {
        receiver = nil
    }
}
