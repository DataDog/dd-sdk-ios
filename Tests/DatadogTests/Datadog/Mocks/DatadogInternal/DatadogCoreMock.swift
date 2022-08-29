/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

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

extension DatadogCoreMock: DatadogCoreProtocol {
    // MARK: V2 interface

    func send(message: FeatureMessage, else fallback: () -> Void) {
        let receivers = v1Features.values
            .compactMap { $0 as? V1Feature }
            .filter { $0.messageReceiver.receive(message: message, from: self) }

        if receivers.isEmpty {
            fallback()
        }
    }
}

extension DatadogCoreMock: DatadogV1CoreProtocol {
    // MARK: V1 interface

    struct Scope: FeatureV1Scope {
        let context: DatadogContext
        let writer: Writer

        func eventWriteContext(_ block: @escaping (DatadogContext, Writer) throws -> Void) {
            XCTAssertNoThrow(try block(context, writer), "Encountered an error when executing `eventWriteContext`")
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

    func scope<T>(for featureType: T.Type) -> FeatureV1Scope? {
        guard let context = context else {
            return nil
        }

        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return Scope(context: .init(context), writer: feature.storage.writer)
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

    init(_ v2: DatadogContext, dateProvider: DateProvider = SystemDateProvider()) {
        self.init(
            site: v2.site,
            clientToken: v2.clientToken,
            service: v2.service,
            env: v2.env,
            version: v2.version,
            source: v2.source,
            sdkVersion: v2.sdkVersion,
            ciAppOrigin: v2.ciAppOrigin,
            applicationName: v2.applicationName,
            applicationBundleIdentifier: v2.applicationBundleIdentifier,
            sdkInitDate: v2.sdkInitDate,
            device: v2.device,
            dateProvider: dateProvider,
            dateCorrector: DateCorrectorMock(offset: v2.serverTimeOffset),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: v2.networkConnectionInfo),
            carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: v2.carrierInfo),
            userInfoProvider: UserInfoProvider.mockWith(userInfo: v2.userInfo ?? .empty),
            appStateListener: AppStateListenerMock(history: v2.applicationStateHistory),
            launchTimeProvider: LaunchTimeProviderMock(
                launchTime: v2.launchTime.launchTime,
                isActivePrewarm: v2.launchTime.isActivePrewarm
            )
        )
    }
}

extension DatadogContext {
    init(_ v1: DatadogV1Context) {
        self.init(
            site: v1.site,
            clientToken: v1.clientToken,
            service: v1.service,
            env: v1.env,
            version: v1.version,
            source: v1.source,
            sdkVersion: v1.sdkVersion,
            ciAppOrigin: v1.ciAppOrigin,
            serverTimeOffset: v1.dateCorrector.offset,
            applicationName: v1.applicationName,
            applicationBundleIdentifier: v1.applicationBundleIdentifier,
            sdkInitDate: v1.sdkInitDate,
            device: v1.device,
            userInfo: v1.userInfoProvider.value,
            launchTime: .init(
                launchTime: v1.launchTimeProvider.launchTime,
                isActivePrewarm: v1.launchTimeProvider.isActivePrewarm
            ),
            applicationStateHistory: v1.appStateListener.history,
            networkConnectionInfo: v1.networkConnectionInfoProvider.current,
            carrierInfo: v1.carrierInfoProvider.current,
            batteryStatus: nil,
            isLowPowerModeEnabled: false
        )
    }
}
