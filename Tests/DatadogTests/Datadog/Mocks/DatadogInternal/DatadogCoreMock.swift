/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

@testable import Datadog

internal final class DatadogCoreMock: Flushable {
    /// Registry for Features.
    private var features: [String: (
        feature: DatadogFeature,
        writer: Writer
    )] = [:]

    /// Registry for Feature Integrations.
    private var integrations: [String: DatadogFeatureIntegration] = [:]

    private var v1Features: [String: Any] = [:]

    @_pthread_rwlock
    var context: DatadogContext {
        didSet { send(message: .context(context)) }
    }

    /// This queue used for invoking Feature scopes.
    var queue: DispatchQueue?

    /// Creates a DatadogCore mock.
    ///
    /// - Parameters:
    ///   - context: The default context.
    ///   - queue: The queue for invoking Feature scopes. If `nil`, the scope will be
    ///   in sync.
    init(
        context: DatadogContext = .mockAny(),
        queue: DispatchQueue? = nil
    ) {
        self.context = context
        self.queue = queue
    }

    /// Flush resgistered features.
    ///
    /// The method will also call `flush` on any `Flushable` registered
    /// feature.
    func flush() {
        all(Flushable.self).forEach { $0.flush() }
        v1Features = [:]
    }

    /// Gets all registered feature of a given type.
    ///
    /// - Parameter type: The desired feature type.
    /// - Returns: Array of feature.
    func all<T>(_ type: T.Type) -> [T] {
        v1Features.values.compactMap { $0 as? T }
    }
}

extension DatadogCoreMock: DatadogCoreProtocol {
    // MARK: V2 interface

    func register(feature: DatadogFeature) throws {
        features[feature.name] = (
            feature: feature,
            writer: InMemoryWriter()
        )

        feature.messageReceiver.receive(message: .context(context), from: self)
    }

    func feature<T>(named name: String, type: T.Type) -> T? where T: DatadogFeature {
        features[name]?.feature as? T
    }

    func register(integration: DatadogFeatureIntegration) throws {
        integrations[integration.name] = integration
        integration.messageReceiver.receive(message: .context(context), from: self)
    }

    func integration<T>(named name: String, type: T.Type) -> T? where T: DatadogFeatureIntegration {
        integrations[name] as? T
    }

    /// no-op
    func scope(for feature: String) -> FeatureScope? { nil }

    func set(feature: String, attributes: @escaping () -> FeatureBaggage) {
        context.featuresAttributes[feature] = attributes()
    }

    func send(message: FeatureMessage, else fallback: () -> Void) {
        let receivers = (
            v1Features.values.compactMap { $0 as? V1Feature }.map(\.messageReceiver)
            + features.values.map(\.feature.messageReceiver)
            + integrations.values.map(\.messageReceiver)
        ).filter { $0.receive(message: message, from: self) }

        if receivers.isEmpty {
            fallback()
        }
    }
}

extension DatadogCoreMock: DatadogV1CoreProtocol {
    // MARK: V1 interface

    struct Scope: FeatureScope {
        let queue: DispatchQueue?
        let context: DatadogContext
        let writer: Writer

        func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
            let block = {
                do {
                    try block(context, writer)
                } catch {
                    XCTFail("Encountered an error when executing `eventWriteContext`. error: \(error)")
                }
            }

            queue?.async(execute: block) ?? block()
        }
    }

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }

    func scope<T>(for featureType: T.Type) -> FeatureScope? {
        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return Scope(
            queue: queue,
            context: context,
            writer: feature.storage.writer
        )
    }
}
