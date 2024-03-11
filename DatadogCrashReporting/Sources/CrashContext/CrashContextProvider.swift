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

    private var logAttributes: AnyCodable? {
        didSet { _context?.lastLogAttributes = logAttributes }
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
        static let viewEvent = "rum-view-event"

        /// The key references a `true` value if the RUM view is reset.
        static let viewReset = "rum-view-reset"

        /// The key references RUM session state.
        /// The state associated with the key conforms to `Codable`.
        static let sessionState = "rum-session-state"

        /// This key references the global log attributes
        static let logAttributes = "global-log-attributes"
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            update(context: context)
        case .baggage(let label, let baggage) where label == RUMBaggageKeys.viewEvent:
            updateRUMView(with: baggage, to: core)
        case .baggage(let label, let baggage) where label == RUMBaggageKeys.viewReset:
            resetRUMView(with: baggage, to: core)
        case .baggage(let label, let baggage) where label == RUMBaggageKeys.sessionState:
            updateSessionState(with: baggage, to: core)
        case .baggage(let label, let baggage) where label == RUMBaggageKeys.logAttributes:
            updateLogAttributes(with: baggage, to: core)
        default:
            return false
        }

        return true
    }

    /// Updates crash context.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext) {
        queue.async {
            let crashContext = CrashContext(
                context,
                lastRUMViewEvent: self.viewEvent,
                lastRUMSessionState: self.sessionState,
                lastLogAttributes: self.logAttributes
            )

            if crashContext != self._context {
                self._context = crashContext
            }
        }
    }

    private func updateRUMView(with baggage: FeatureBaggage, to core: DatadogCoreProtocol) {
        queue.async { [weak core] in
            do {
                self.viewEvent = try baggage.decode(type: AnyCodable.self)
            } catch {
                core?.telemetry
                    .error("Fails to decode RUM view event from Crash Reporting", error: error)
            }
        }
    }

    private func resetRUMView(with baggage: FeatureBaggage, to core: DatadogCoreProtocol) {
        queue.async { [weak core] in
            do {
                if try baggage.decode(type: Bool.self) {
                    self.viewEvent = nil
                }
            } catch {
                core?.telemetry
                    .error("Fails to decode RUM view reset from Crash Reporting", error: error)
            }
        }
    }

    private func updateSessionState(with baggage: FeatureBaggage, to core: DatadogCoreProtocol) {
        queue.async { [weak core] in
            do {
                self.sessionState = try baggage.decode(type: AnyCodable.self)
            } catch {
                core?.telemetry
                    .error("Fails to decode RUM session state from Crash Reporting", error: error)
            }
        }
    }

    private func updateLogAttributes(with baggage: FeatureBaggage, to core: DatadogCoreProtocol) {
        queue.async { [weak core] in
            do {
                self.logAttributes = try baggage.decode(type: AnyCodable.self)
            } catch {
                core?.telemetry
                    .error("Fails to decode log attributes from Crash Reporting", error: error)
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
