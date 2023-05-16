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

    private var viewEvent: AnyCodable? {
        didSet { _context?.lastRUMViewEvent = viewEvent }
    }

    private var sessionState: AnyCodable? {
        didSet { _context?.lastRUMSessionState = sessionState }
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
    /// Defines keys referencing RUM baggage in `DatadogContext.featuresAttributes`.
    internal enum RUMBaggageKeys {
        /// The key references RUM view event.
        /// The view event associated with the key conforms to `Codable`.
        static let viewEvent = "view-event"

        /// The key references a `true` value if the RUM view is reset.
        static let viewReset = "view-reset"

        /// The key references RUM session state.
        /// The state associated with the key conforms to `Codable`.
        static let sessionState = "session-state"
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context)
        case .custom(let key, let attributes) where key == "rum":
            return rum(attributes: attributes, to: core)
        default:
            return false
        }
    }

    /// Updates crash context.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext) -> Bool {
        queue.async {
            let crashContext = CrashContext(
                context,
                lastRUMViewEvent: self.viewEvent,
                lastRUMSessionState: self.sessionState
            )

            if crashContext != self._context {
                self._context = crashContext
            }
        }

        return true
    }

    private func rum(attributes: FeatureBaggage, to core: DatadogCoreProtocol) -> Bool {
        if attributes["view-reset", type: Bool.self] == true {
            queue.async { self.viewEvent = nil }
            return true
        }

        if let event = attributes[RUMBaggageKeys.viewEvent, type: AnyCodable.self] {
            queue.async { self.viewEvent = event }
            return true
        }

        if let state = attributes["session-state", type: AnyCodable.self] {
            queue.async { self.sessionState = state }
            return true
        }

        return false
    }
}
