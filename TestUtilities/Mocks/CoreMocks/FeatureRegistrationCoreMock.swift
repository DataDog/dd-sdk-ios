/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Core mock that only allows registering and retrieving features.
///
/// Usage:
///
///     let core = FeatureRegistrationCoreMock()
///     let feature = MyCustomFeature()
///
///     try core.register(feature: feature)
///     
///     core.get(feature: MyCustomFeature.self) === feature // true
///     core.get(feature: OtherFeature.self) // returns nil
///
/// **Note:** If you need different capabilities, check other available core mocks,
/// before you consider adding it here.
public class FeatureRegistrationCoreMock: DatadogCoreProtocol {
    /// Counts references to this mock, so we can test if there are no memory leaks.
    public static var referenceCount = 0

    public internal(set) var registeredFeatures: [DatadogFeature] = []

    public init() {
        FeatureRegistrationCoreMock.referenceCount += 1
    }

    deinit {
        FeatureRegistrationCoreMock.referenceCount -= 1
    }

    // MARK: - Supported

    public func register<T>(feature: T) throws where T : DatadogFeature {
        registeredFeatures.append(feature)
    }

    public func get<T>(feature type: T.Type) -> T? where T : DatadogFeature {
        return registeredFeatures.firstElement(of: type)
    }

    // MARK: - Unsupported

    public func scope(for feature: String) -> FeatureScope? {
        // not supported - use different type of core mock if you need this
        return nil
    }

    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        // not supported - use different type of core mock if you need this
    }

    public func send(message: DatadogInternal.FeatureMessage, else fallback: @escaping () -> Void) {
        // not supported - use different type of core mock if you need this
    }
}
