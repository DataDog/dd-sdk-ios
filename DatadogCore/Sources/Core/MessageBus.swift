/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The message-bus sends messages to a set of registered receivers.
///
/// The bus is an actor whose isolation replaces the former `DispatchQueue`-based
/// synchronisation. Receivers are dispatched synchronously within the actor —
/// a slow receiver can delay delivery to the others but cannot cause data races.
internal actor MessageBus {
    /// A weak core reference.
    private weak var core: DatadogCoreProtocol?

    /// Receivers keyed by feature name.
    private var receivers: [String: FeatureMessageReceiver] = [:]

    /// The current configuration.
    ///
    /// The message-bus accumulates configuration by merging. A message
    /// with the configuration will be dispatched once after a specified delay,
    /// 5 seconds by default.
    private var configuration: ConfigurationTelemetry?

    /// Creates a bus and schedules the deferred configuration dispatch.
    ///
    /// - Parameter configurationDispatchDelay: The delay in nanoseconds before
    ///   dispatching accumulated configuration telemetry. Defaults to 5 seconds.
    init(configurationDispatchDelay: UInt64 = 5_000_000_000) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: configurationDispatchDelay)
            await self?.dispatchConfiguration()
        }
    }

    /// Connects the core to the bus.
    ///
    /// The message-bus keeps a weak reference to the core.
    ///
    /// - Parameter core: The core reference.
    func connect(core: DatadogCoreProtocol) {
        self.core = core
    }

    // MARK: - Receivers

    /// Registers a receiver with a given key.
    ///
    /// - Parameters:
    ///   - receiver: The message receiver.
    ///   - key: The key associated with the receiver.
    func connect(_ receiver: FeatureMessageReceiver, forKey key: String) {
        receivers[key] = receiver
    }

    /// Removes the receiver for the given key.
    ///
    /// - Parameter key: The key to remove along with its associated receiver.
    func disconnect(forKey key: String) {
        receivers.removeValue(forKey: key)
    }

    // MARK: - Sending

    /// Sends a message to all receivers registered in this bus.
    ///
    /// If no receiver handled the message the fallback closure is invoked.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - fallback: The fallback closure to call when the message could not be
    ///               processed by any receiver on the bus.
    func send(message: FeatureMessage, else fallback: @escaping @Sendable () -> Void = {}) {
        if case .telemetry(let telemetry) = message,
           case .configuration(let config) = telemetry {
            return save(configuration: config)
        }

        guard let core else { return }

        let handled = receivers.values.filter {
            $0.receive(message: message, from: core)
        }

        if handled.isEmpty {
            fallback()
        }
    }

    /// Sends the initial context to a specific receiver.
    ///
    /// - Parameters:
    ///   - context: The current SDK context.
    ///   - key: The receiver key.
    func sendInitialContext(_ context: DatadogContext, forKey key: String) {
        guard let core else { return }
        receivers[key]?.receive(message: .context(context), from: core)
    }

    // MARK: - Configuration Telemetry

    /// Saves the current Configuration Telemetry by merging.
    private func save(configuration: ConfigurationTelemetry) {
        self.configuration = self.configuration.map {
            $0.merged(with: configuration)
        } ?? configuration
    }

    /// Dispatches accumulated configuration telemetry to all receivers.
    private func dispatchConfiguration() {
        guard let core, let configuration else { return }

        let configMessage: FeatureMessage = .telemetry(.configuration(configuration))

        receivers.values.forEach {
            $0.receive(message: configMessage, from: core)
        }
    }
}

extension MessageBus: Flushable {
    /// Awaits completion of all pending actor operations.
    ///
    /// **blocks the caller thread**
    nonisolated func flush() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await self.barrierFlush()
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// Actor-isolated no-op whose execution proves all prior work has completed.
    private func barrierFlush() { }
}
