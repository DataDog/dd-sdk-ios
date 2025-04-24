/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Single-Feature core mock is a `PassthroughCoreMock` with the ability to register
/// a single Feature instance.
///
/// The Single-Feature can be useful if you need to register and retrieve a Feature during tests.
///
/// Usage:
///
///         let feature = MyCustomFeature()
///         let core = SingleFeatureCoreMock(feature: feature)
///         core.scope(for: "my-custom-feature")?.eventWriteContext { context, writer in
///             // will open a scope for the custom Feature only.
///         }
///
/// The Single-Feature core allow registering and retrieving a single Feature type.
///
///     let feature = MyCustomFeature()
///     try core.register(feature: feature)
///     core.get(feature: MyCustomFeature.self) // returns feature instance
///
public final class SingleFeatureCoreMock<Feature>: PassthroughCoreMock, @unchecked Sendable where Feature: DatadogFeature {
    /// The single Feature.
    private var feature: Feature?

    /// Creates a Single-Feature core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.
    ///   - feature: The registered Feature.
    ///   - expectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked.
    public required init(
        context: DatadogContext = .mockAny(),
        dataStore: DataStore = NOPDataStore(),
        feature: Feature? = nil,
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) {
        self.feature = feature

        super.init(
            context: context,
            dataStore: dataStore,
            messageReceiver: messageReceiver
        )
    }

    /// Creates a Single-Feature core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.
    ///   - expectation: The test exepection to fullfill when `eventWriteContext`
    ///                  is invoked.
    public required init(
        context: DatadogContext = .mockAny(),
        dataStore: DataStore = NOPDataStore(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) {
        self.feature = nil

        super.init(
            context: context,
            dataStore: dataStore,
            messageReceiver: messageReceiver
        )
    }

    override public func register<T>(feature: T) throws where T: DatadogFeature {
        self.feature = feature as? Feature
    }

    override public func feature<T>(named name: String, type: T.Type) -> T? {
        feature as? T
    }

    override public func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        guard T.name == Feature.name else {
            return NOPFeatureScope()
        }
        return super.scope(for: featureType)
    }
}
