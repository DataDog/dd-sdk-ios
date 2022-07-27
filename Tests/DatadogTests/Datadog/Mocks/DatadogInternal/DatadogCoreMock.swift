/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@testable import Datadog

internal final class DatadogCoreMock: Flushable {
    private var v1Features: [String: Any] = [:]

    var context: DatadogV1Context?

    init(context: DatadogV1Context? = .mockAny()) {
        self.context = context
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

extension DatadogCoreMock: DatadogV1CoreProtocol {
    // MARK: V1 interface

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }

    func scope<T>(for featureType: T.Type) -> FeatureV1Scope? {
        guard let context = context else {
            return nil
        }

        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return DatadogCoreFeatureScope(
            context: context,
            storage: feature.storage
        )
    }
}

extension DatadogV1Context: AnyMockable {
    static func mockAny() -> DatadogV1Context {
        return mockWith()
    }

    static func mockWith(
        site: DatadogSite? = .mockAny(),
        clientToken: String = .mockAny(),
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        source: String = .mockAny(),
        sdkVersion: String = .mockAny(),
        ciAppOrigin: String? = nil,
        applicationName: String = .mockAny(),
        applicationBundleIdentifier: String = .mockAny(),
        sdkInitDate: Date = Date(),
        device: DeviceInfo = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        dateCorrector: DateCorrector = DateCorrectorMock(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        appStateListener: AppStateListening = AppStateListenerMock.mockAny(),
        launchTimeProvider: LaunchTimeProviderType = LaunchTimeProviderMock.mockAny()
    ) -> DatadogV1Context {
        DatadogV1Context(
            site: site,
            clientToken: clientToken,
            service: service,
            env: env,
            version: version,
            source: source,
            sdkVersion: sdkVersion,
            ciAppOrigin: ciAppOrigin,
            applicationName: applicationName,
            applicationBundleIdentifier: applicationBundleIdentifier,
            sdkInitDate: sdkInitDate,
            device: device,
            dateProvider: dateProvider,
            dateCorrector: dateCorrector,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            userInfoProvider: userInfoProvider,
            appStateListener: appStateListener,
            launchTimeProvider: launchTimeProvider
        )
    }
}
