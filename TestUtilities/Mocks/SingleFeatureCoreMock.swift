/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
import DatadogInternal

/// Single-Feature core mocks feature-scope for a single `Feature` type.
public final class SingleFeatureCoreMock<Feature>: DatadogCoreProtocol, FeatureScope where Feature: DatadogFeature {
    /// The single Feature.
    private var feature: Feature?

    private let writer = FileWriterMock()

    /// Current context that will be passed to feature-scopes.
    @ReadWriteLock
    public var context: DatadogContext {
        didSet { send(message: .context(context)) }
    }

    public init(
        context: DatadogContext = .mockAny(),
        feature: Feature? = nil
    ) {
        self.context = context
        self.feature = feature
        feature?.messageReceiver.receive(message: .context(context), from: self)
    }

    public func register<T>(feature: T) throws where T : DatadogInternal.DatadogFeature {
        self.feature = feature as? Feature
    }

    public func get<T>(feature type: T.Type) -> T? where T : DatadogInternal.DatadogFeature {
        feature as? T
    }

    public func scope(for feature: String) -> DatadogInternal.FeatureScope? {
        guard feature == Feature.name else {
            return nil
        }
        return self
    }

    public func set(feature: String, attributes: @escaping () -> DatadogInternal.FeatureBaggage) {
        context.featuresAttributes[feature] = attributes()
    }

    public func send(message: DatadogInternal.FeatureMessage, sender: DatadogInternal.DatadogCoreProtocol, else fallback: @escaping () -> Void) {
        guard let feature = feature, feature.messageReceiver.receive(message: message, from: sender) else {
            return fallback()
        }
    }

    /// Execute `block` with the current context and a `writer` to record events.
    ///
    /// - Parameter block: The block to execute.
    public func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: (DatadogContext, Writer) throws -> Void) {
        XCTAssertNoThrow(try block(context, writer), "Encountered an error when executing `eventWriteContext`")
    }

    /// Recorded events from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    public var events: [Encodable] { writer.events }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.events(ofType: type)
    }
}
