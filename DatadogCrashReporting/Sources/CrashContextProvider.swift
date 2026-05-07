/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An interface for writing and reading  the `CrashContext`
internal protocol CrashContextProvider: AnyObject {
    /// Returns current `CrashContext` value.
    var currentCrashContext: CrashContext? { get }
    /// Notifies on `CrashContext` change.
    var onCrashContextChange: (CrashContext) -> Void { set get }
}

/// Manages the `CrashContext` reads and writes in a thread-safe manner.
internal class CrashContextCoreProvider: CrashContextProvider {
    /// Queue for synchronizing `unsafeCrashContext` updates.
    private let queue = DispatchQueue(
        label: "com.datadoghq.crash-context",
        target: .global(qos: .utility)
    )

    /// Unsafe callback instance.
    private var _callback: (CrashContext) -> Void = { _ in }

    /// Unsychronized `CrashContext`. The `queue` must be used to synchronize its mutation.
    private var _context: CrashContext? {
        didSet { _context.map(_callback) }
    }

    private var viewEvent: RUMViewEvent? {
        didSet { _context?.lastRUMViewEvent = viewEvent }
    }

    private var sessionState: RUMSessionState? {
        didSet { _context?.lastRUMSessionState = sessionState }
    }

    private var logAttributes: LogEventAttributes? {
        didSet { _context?.lastLogAttributes = logAttributes }
    }

    private var rumAttributes: RUMEventAttributes? {
        didSet { _context?.lastRUMAttributes = rumAttributes }
    }

    /// Typed-bus subscription handles. Retaining these keeps the closures alive.
    private var subscriptions: [MessageBusSubscription] = []

    // MARK: - CrashContextProviderType

    var currentCrashContext: CrashContext? {
        queue.sync { _context }
    }

    var onCrashContextChange: (CrashContext) -> Void {
        get { queue.sync { self._callback } }
        set { queue.async { self._callback = newValue } }
    }
}

extension CrashContextCoreProvider: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case .context(let context) = message else {
            return false
        }

        update(context: context)
        return true
    }

    /// Updates crash context.
    ///
    /// - Parameter context: The updated core context.
    fileprivate func update(context: DatadogContext) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            let crashContext = CrashContext(
                context,
                lastRUMViewEvent: self.viewEvent,
                lastRUMSessionState: self.sessionState,
                lastRUMAttributes: self.rumAttributes,
                lastLogAttributes: self.logAttributes
            )

            if crashContext != self._context {
                self._context = crashContext
            }
        }
    }
}

// MARK: - Typed-bus subscriptions

extension CrashContextCoreProvider {
    /// Subscribes to all crash-context update messages on the typed bus.
    ///
    /// Call once from `CrashReporting.enableOrThrow`. The returned subscriptions are retained
    /// by the provider and cancelled when it is deallocated.
    func subscribe(to bus: MessageBus) {
        subscriptions = [
            bus.subscribe { [weak self] (message: RUMViewEvent, _) in
                self?.queue.async { self?.viewEvent = message }
            },
            bus.subscribe { [weak self] (_: RUMViewReset, _) in
                self?.queue.async { self?.viewEvent = nil }
            },
            bus.subscribe { [weak self] (message: RUMSessionState, _) in
                self?.queue.async { self?.sessionState = message }
            },
            bus.subscribe { [weak self] (message: RUMEventAttributes, _) in
                self?.queue.async { self?.rumAttributes = message }
            },
            bus.subscribe { [weak self] (message: LogEventAttributes, _) in
                self?.queue.async { self?.logAttributes = message }
            },
        ]
    }
}

extension CrashContextCoreProvider: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
