/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ContextSharingTransformer: FeatureMessageReceiver, ContextValuePublisher {
    private let queue = DispatchQueue(label: "com.datadog.context-sharing-transformer")

    private var sharedContext: SharedContext? = nil
    private var receiver: ContextValueReceiver<SharedContext?>? = nil

    // MARK: - FeatureMessageReceiver

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            let newContext = SharedContext(datadogContext: context)
            queue.sync {
                sharedContext = newContext
            }

            // Call receiver outside of queue.sync to avoid potential deadlocks
            let currentReceiver = queue.sync { receiver }
            currentReceiver?(newContext)
            return true
        default:
            return false
        }
    }

    // MARK: - ContextValuePublisher

    var initialValue: SharedContext? = nil

    func publish(to receiver: @escaping ContextValueReceiver<SharedContext?>) {
        let currentContext = queue.sync { sharedContext }
        queue.sync {
            self.receiver = receiver
            receiver(currentContext)
        }
    }

    func cancel() {
        queue.sync {
            receiver = nil
        }
    }
}
