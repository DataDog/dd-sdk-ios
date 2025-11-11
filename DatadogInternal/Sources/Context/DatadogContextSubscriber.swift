/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A thread-safe subscriber for receiving DatadogContext updates.
///
/// `DatadogContextSubscriber` implements `FeatureMessageReceiver` to listen for context updates
/// on the message bus and provides a callback mechanism to notify subscribers when the context changes.
public final class DatadogContextSubscriber: FeatureMessageReceiver {
    /// The current DatadogContext.
    ///
    /// The context is synchronized using a read-write lock for thread-safe access.
    @ReadWriteLock
    public private(set) var context: DatadogContext?

    /// Callback invoked when the context is updated.
    ///
    /// The callback is synchronized using a read-write lock for thread-safe access.
    @ReadWriteLock
    private var onContextUpdate: ((DatadogContext) -> Void)?

    /// Creates a new instance of `DatadogContextSubscriber`.
    ///
    /// - Parameter onContextUpdate: Optional callback invoked when the context is updated.
    public init(onContextUpdate: ((DatadogContext) -> Void)? = nil) {
        self.onContextUpdate = onContextUpdate
    }

    /// Sets or updates the callback invoked when the context is updated.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// - Parameter callback: The callback to invoke when context is updated.
    public func setOnContextUpdate(_ callback: @escaping (DatadogContext) -> Void) {
        _onContextUpdate.mutate { $0 = callback }
    }

    /// Process messages received from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    /// - Returns: `true` if the message was processed; `false` if it was ignored.
    @discardableResult
    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let newContext):
            return update(context: newContext)
        default:
            return false
        }
    }

    /// Updates the stored context and notifies subscribers.
    ///
    /// - Parameter context: The updated DatadogContext.
    /// - Returns: `true` if the context was updated successfully.
    private func update(context newContext: DatadogContext) -> Bool {
        _context.mutate { $0 = newContext }

        // Invoke callback if set (read the callback in a thread-safe manner)
        let callback = _onContextUpdate.wrappedValue
        callback?(newContext)

        return true
    }
}
