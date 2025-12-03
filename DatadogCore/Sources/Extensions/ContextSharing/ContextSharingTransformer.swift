/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ContextSharingTransformer: FeatureMessageReceiver, ContextValuePublisher {
    @ReadWriteLock
    private var sharedContext: SharedContext? = nil {
        didSet {
            receiver?(sharedContext)
        }
    }

    // MARK: - FeatureMessageReceiver

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            let newContext = SharedContext(datadogContext: context)
            _sharedContext.mutate { $0 = newContext }
            return true
        default:
            return false
        }
    }

    // MARK: - ContextValuePublisher

    private var receiver: ContextValueReceiver<SharedContext?>? = nil

    var initialValue: SharedContext? = nil

    func publish(to receiver: @escaping ContextValueReceiver<SharedContext?>) {
        receiver(sharedContext)
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
