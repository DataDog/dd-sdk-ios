/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The RUM context received from `DatadogCore`.
internal struct RUMContext: Decodable, Equatable {
    internal struct IDs: Decodable, Equatable {
        enum CodingKeys: String, CodingKey {
            case applicationID = "application.id"
            case sessionID = "session.id"
            case viewID = "view.id"
        }
        /// Current RUM application ID - standard UUID string, lowecased.
        let applicationID: String
        /// Current RUM session ID - standard UUID string, lowecased.
        let sessionID: String
        /// Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
        let viewID: String?
    }

    enum CodingKeys: String, CodingKey {
        case ids = "ids"
        case viewServerTimeOffset = "server_time_offset"
    }

    /// Wrapper for all RUM related IDs
    let ids: IDs

    /// Current view related server time offset
    let viewServerTimeOffset: TimeInterval?
}

/// An observer notifying on`RUMContext` changes.
internal protocol RUMContextObserver {
    /// Starts notifying on distinct changes to `RUMContext`.
    ///
    /// - Parameters:
    ///   - queue: a queue to call `notify` block on
    ///   - notify: a closure receiving new `RUMContext` or `nil` if current RUM session is not sampled
    func observe(on queue: Queue, notify: @escaping (RUMContext?) -> Void)
}

/// Receives RUM context from `DatadogCore` and notifies it through `RUMContextObserver` interface.
internal class RUMContextReceiver: FeatureMessageReceiver, RUMContextObserver {
    /// Notifies new `RUMContext` or `nil` if current RUM session is not sampled.
    private var onNew: ((RUMContext?) -> Void)?
    private var previous: RUMContext?

    // MARK: - FeatureMessageReceiver

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard let rumBaggage = message.contextMessage?.rumBaggage else {
            // No RUM baggage in the message
            return false
        }

        // Extract the `RUMContext` or `nil` if RUM session is not sampled:
        let new = rumBaggage.rumContext

        // Notify only if it has changed:
        if new != previous {
            onNew?(new)
            previous = new
        }

        return true
    }

    // MARK: - RUMContextObserver

    func observe(on queue: Queue, notify: @escaping (RUMContext?) -> Void) {
        onNew = { new in
            queue.run {
                notify(new)
            }
        }
    }
}

// MARK: - Extracting RUM context from `DatadogCore` message

private extension FeatureMessage {
    var contextMessage: DatadogContext? {
        guard case let .context(datadogContext) = self else {
            return nil
        }
        return datadogContext
    }
}

private extension DatadogContext {
    var rumBaggage: FeatureBaggage? {
        return featuresAttributes[RUMDependency.rumBaggageKey]
    }
}

private extension FeatureBaggage {
    var rumContext: RUMContext? { try? unwrap() }
}

extension FeatureBaggage {
    func unwrap<T>() throws -> T where T: Decodable {
        let decoder = AnyDecoder()
        return try decoder.decode(from: attributes)
    }
}
