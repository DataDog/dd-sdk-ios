/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A thread-safe subscriber for receiving contexts updates in obj-c.
/// This is done mainly to improve capabilities of cross-platform SDKs.
///
/// `DDSharedContextPublisher` implements `FeatureMessageReceiver` to listen for context updates
/// on the message bus and provides a callback mechanism to notify subscribers when the context changes.
@_spi(Internal)
public final class DDSharedContextPublisher: NSObject, FeatureMessageReceiver {
    @ReadWriteLock
    @objc private(set) var context: DDSharedContext?

    private var onContextUpdate: ((DDSharedContext) -> Void)?

    @objc
    init(onContextUpdate: ((DDSharedContext) -> Void)? = nil) {
        self.onContextUpdate = onContextUpdate
    }

    @discardableResult
    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let newContext):
            return update(context: newContext)
        default:
            return false
        }
    }

    private func update(context newContext: DatadogContext) -> Bool {
        let sharedContext = DDSharedContext(swiftContext: newContext)
        _context.mutate { $0 = sharedContext }
        onContextUpdate?(sharedContext)
        return true
    }
}
