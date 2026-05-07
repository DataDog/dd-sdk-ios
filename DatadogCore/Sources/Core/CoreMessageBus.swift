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
internal final class CoreMessageBus {
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

    /// A closure that delivers a `BusMessage` to a single subscriber.
    ///
    /// Captures the receiver strongly and performs the runtime cast from `Any`
    /// to the receiver's expected `Message` type.
    private typealias Dispatch = (Any, DatadogCoreProtocol) -> Void

    /// Typed `BusMessageReceiver` subscribers grouped by `BusMessage.key`.
    ///
    /// The outer key is the `BusMessage.key` of the message kind a subscriber
    /// is registered for; the inner key is the receiver's object identity. The
    /// keyed layout means dispatch only iterates receivers for the matching
    /// message kind instead of the full subscriber set.
    ///
    /// Each `Dispatch` captures its receiver strongly, so the bus retains
    /// subscribers until they are explicitly removed via `unsubscribe(receiver:)`.
    ///
    /// Must be accessed within the queue.
    private var receivers: [String: [ObjectIdentifier: Dispatch]] = [:]

    /// The current configuration.
    ///
    /// The message-bus wil accumulate configuration by merge. A message
    /// with the configuration will be dispatched once after a specified delay,
    /// 5 seconds by default.
    ///
    /// The configuration **must** be accessed within the queue.
    private var configuration: ConfigurationTelemetry?

    /// Creates a bus for the given core.
    ///
    /// The message-bus keeps a weak reference to the core.
    /// - Parameter configurationDispatchTime: The delay to dispatch the
    /// configuration telemetry
    init(configurationDispatchTime: DispatchTimeInterval = .seconds(5)) {
        queue.asyncAfter(deadline: .now() + configurationDispatchTime) {
            guard let core = self.core, let configuration = self.configuration else {
                return
            }

            self.bus.values.forEach {
                $0.receive(message: .telemetry(.configuration(configuration)), from: core)
            }
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

        queue.async {
            guard let core = self.core else {
                return
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
        queue.async {
            // merge with the current configuration if any
            self.configuration = self.configuration.map {
                $0.merged(with: configuration)
            } ?? configuration
        }
    }
}

extension CoreMessageBus: MessageBus {
    /// Adds `receiver` to the bucket for `Receiver.Message.key`.
    ///
    /// The receiver is retained by the bus (via the captured closure) until
    /// `unsubscribe(receiver:)` is called. Re-subscribing the same instance for
    /// the same message kind replaces the previous subscription — entries are
    /// keyed by object identity.
    func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        queue.async {
            let id = ObjectIdentifier(receiver)
            self.receivers[Receiver.Message.key, default: [:]][id] = { message, core in
                guard let typed = message as? Receiver.Message else {
                    return
                }
                receiver.receive(message: typed, from: core)
            }
        }
    }

    /// Removes `receiver` from the bucket for `Receiver.Message.key`.
    ///
    /// No-op if `receiver` is not currently subscribed. Empty buckets are
    /// pruned to keep the registry tidy.
    func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        queue.async {
            let key = Receiver.Message.key
            let id = ObjectIdentifier(receiver)
            self.receivers[key]?.removeValue(forKey: id)
            if self.receivers[key]?.isEmpty == true {
                self.receivers.removeValue(forKey: key)
            }
        }
    }

    /// Publishes `message` to every receiver in the bucket for `Message.key`.
    ///
    /// `fallback` is invoked when the bus has no core, or when the bucket is
    /// empty. Delivery is dispatched on the bus's serial queue.
    func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage {
        queue.async {
            guard let core = self.core else {
                return fallback()
            }
            guard let bucket = self.receivers[Message.key], !bucket.isEmpty else {
                return fallback()
            }
            bucket.values.forEach { dispatch in
                dispatch(message, core)
            }
        }
    }
}

extension CoreMessageBus: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
