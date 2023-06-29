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

extension MessageBus: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
