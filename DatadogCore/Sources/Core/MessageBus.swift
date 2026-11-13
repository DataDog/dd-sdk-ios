/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The message-bus sends messages to a set of registered receivers.
///
/// The bus dispatches messages on a serial queue.
internal final class MessageBus {
    /// The message bus GDC queue.
    let queue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-message-bus",
        target: .global(qos: .utility)
    )

    /// A weak core reference.
    ///
    /// The core **must** be accessed within the queue.
    private weak var core: DatadogCoreProtocol?

    /// The message bus used to dispatch messages to registered features.
    ///
    /// The bus **must** be accessed within the queue.
    private var bus: [String: FeatureMessageReceiver] = [:]

    /// The current configuration.
    ///
    /// The message-bus wil accumulate configuration by merge. A message
    /// with the configuration will be dispatched once after a specified delay,
    /// 5 seconds by default.
    ///
    /// The configuration **must** be accessed within the queue.
    private var configuration: ConfigurationTelemetry?

    /// Whether the bus was disconnected.
    ///
    /// It is set synchronously by `disconnect()`, so messages already queued are not delivered.
    @ReadWriteLock
    private var isDisconnected = false

    /// Keeps sudden termination disabled while a message is queued, as it can carry data to write.
    private let suddenTermination: SuddenTerminationControl

    /// Whether the configuration telemetry was delivered. It is delivered once.
    ///
    /// It **must** be accessed within the queue.
    private var isConfigurationDispatched = false

    /// Creates a bus for the given core.
    ///
    /// The message-bus keeps a weak reference to the core.
    /// - Parameters:
    ///   - configurationDispatchTime: The delay to dispatch the configuration telemetry
    ///   - suddenTermination: Disables sudden termination until queued messages are delivered.
    init(
        configurationDispatchTime: DispatchTimeInterval = .seconds(5),
        suddenTermination: SuddenTerminationControl = ProcessSuddenTerminationControl()
    ) {
        self.suddenTermination = suddenTermination
        queue.asyncAfter(deadline: .now() + configurationDispatchTime) {
            self.dispatchConfiguration()
        }
    }

    /// Delivers the configuration telemetry now, if it was not delivered yet, because the app terminates
    /// before the dispatch delay ends. **Blocks the caller thread.**
    func dispatchPendingConfiguration() {
        queue.sync {
            dispatchConfiguration()
        }
    }

    /// Delivers the configuration telemetry once. Runs on the queue.
    private func dispatchConfiguration() {
        guard !isConfigurationDispatched, !isDisconnected, let core = core, let configuration = configuration else {
            return
        }
        isConfigurationDispatched = true

        bus.values.forEach {
            $0.receive(message: .telemetry(.configuration(configuration)), from: core)
        }
    }

    /// Connects the core to the bus.
    ///
    /// The message-bus keeps a weak reference to the core.
    ///
    /// - Parameter core: The core ference.
    func connect(core: DatadogCoreProtocol) {
        queue.async { self.core = core }
    }

    /// Connects a receiver with a given key.
    ///
    /// - Parameters:
    ///   - receiver: The message receiver.
    ///   - key: The key associated with the receiver.
    func connect(_ receiver: FeatureMessageReceiver, forKey key: String) {
        queue.async { self.bus[key] = receiver }
    }

    /// Removes the given key and its associated receiver from the bus.
    ///
    /// - Parameter key: The key to remove along with its associated receiver.
    func removeReceiver(forKey key: String) {
        queue.async { self.bus.removeValue(forKey: key) }
    }

    /// Delivers a message to a single receiver, unless the bus is disconnected by then.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - receiver: The receiver to deliver the message to.
    func deliver(_ message: FeatureMessage, to receiver: FeatureMessageReceiver) {
        queue.async {
            guard !self.isDisconnected, let core = self.core else {
                return
            }
            _ = receiver.receive(message: message, from: core)
        }
    }

    /// Disconnects the core and all receivers from the bus.
    ///
    /// Messages that are queued or sent after disconnection are not delivered: their fallback is invoked instead.
    /// The pending configuration telemetry is not dispatched. A delivery already in progress completes.
    func disconnect() {
        isDisconnected = true
        queue.async {
            self.core = nil
            self.bus = [:]
            self.configuration = nil
        }
    }

    /// Sends a message to receivers registered in this bus.
    ///
    /// If the message could not be processed by any registered feature, the fallback closure
    /// will be invoked. Do not make any assumption on which thread the fallback is called.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - fallback: The fallback closure to call when the message could not be
    ///               processed by any Features on the bus.
    func send(message: FeatureMessage, else fallback: @escaping () -> Void = {}) {
        if  // Configuration Telemetry Message
            case .telemetry(let telemetry) = message,
            case .configuration(let configuration) = telemetry {
            return save(configuration: configuration)
        }

        // A receiver that writes the message opens its event write context while handling it,
        // which keeps sudden termination disabled until the write.
        suddenTermination.async(on: queue) {
            guard !self.isDisconnected, let core = self.core else {
                return fallback() // no feature can process the message
            }

            let receivers = self.bus.values.filter {
                $0.receive(message: message, from: core)
            }

            if receivers.isEmpty {
                fallback()
            }
        }
    }

    /// Saves to current Configuration Telemetry.
    ///
    /// The configuration can be partial, the bus supports accumulation of
    /// configuration for lazy initialization of the SDK.
    ///
    /// - Parameter configuration: The SDK configuration.
    private func save(configuration: ConfigurationTelemetry) {
        // It does not hold sudden termination: a hold would disable it for the first seconds of every launch,
        // and only this telemetry is lost when the app terminates suddenly before the dispatch delay ends.
        queue.async {
            // merge with the current configuration if any
            self.configuration = self.configuration.map {
                $0.merged(with: configuration)
            } ?? configuration
        }
    }
}

extension MessageBus: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
