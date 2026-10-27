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

    private var viewEvent: RUMViewEvent?

    private var isRUMSessionStopped = false

    private var sessionState: RUMSessionState? {
        didSet { _context?.lastRUMSessionState = sessionState }
    }

    private var logAttributes: LogEventAttributes? {
        didSet { _context?.lastLogAttributes = logAttributes }
    }

    private var rumAttributes: RUMEventAttributes? {
        didSet { _context?.lastRUMAttributes = rumAttributes }
    }

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
        switch message {
        case .context(let context):
            update(context: context)
        case let .payload(viewEvent as RUMViewEvent):
            // A new RUM view means tracking resumed, if it was stopped with `stopSession()`.
            queue.async { self.update(viewEvent: viewEvent, isRUMSessionStopped: false) }
        case let .payload(message as String) where message == RUMPayloadMessages.viewReset:
            queue.async { self.update(viewEvent: nil, isRUMSessionStopped: self.isRUMSessionStopped) }
        case let .payload(message as String) where message == RUMPayloadMessages.sessionStop:
            queue.async { self.update(viewEvent: nil, isRUMSessionStopped: true) }
        case let .payload(sessionState as RUMSessionState):
            queue.async { self.sessionState = sessionState }
        case let .payload(rumAttributes as RUMEventAttributes):
            queue.async { self.rumAttributes = rumAttributes }
        case let .payload(logAttributes as LogEventAttributes):
            queue.async { self.logAttributes = logAttributes }
        default:
            return false
        }

        return true
    }

    /// Updates the last RUM view and the session stop together, so the crash context is published once.
    /// Must be called on `queue`.
    private func update(viewEvent: RUMViewEvent?, isRUMSessionStopped: Bool) {
        self.viewEvent = viewEvent
        self.isRUMSessionStopped = isRUMSessionStopped

        guard var context = _context else {
            return
        }
        context.lastRUMViewEvent = viewEvent
        context.isRUMSessionStopped = isRUMSessionStopped
        _context = context
    }

    /// Updates crash context.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            let crashContext = CrashContext(
                context,
                lastRUMViewEvent: self.viewEvent,
                lastRUMSessionState: self.sessionState,
                lastRUMAttributes: self.rumAttributes,
                lastLogAttributes: self.logAttributes,
                isRUMSessionStopped: self.isRUMSessionStopped
            )

            if crashContext != self._context {
                self._context = crashContext
            }
        }
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
