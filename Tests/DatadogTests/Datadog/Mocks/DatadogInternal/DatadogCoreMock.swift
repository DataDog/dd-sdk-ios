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

    var legacyContext: DatadogV1Context? {
        .init(context)
    }

    var context: DatadogContext {
        get { synchronize { _context } }
        set { synchronize { _context = newValue } }
    }

    /// ordered/non-recursive lock on the context.
    private let lock = NSLock()
    private var _context: DatadogContext

    init(context: DatadogContext = .mockAny()) {
        _context = context
    }

    private func synchronize<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
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

    func set(feature: String, attributes: @escaping () -> FeatureBaggage) {
        context.featuresAttributes[feature] = attributes()
    }

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

        func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
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
        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return Scope(context: context, writer: feature.storage.writer)
    }
}

extension DatadogV1Context: AnyMockable {
    static func mockAny() -> DatadogV1Context {
        return mockWith()
    }

    static func mockWith(
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        source: String = .mockAny(),
        sdkVersion: String = .mockAny(),
        device: DeviceInfo = .mockAny(),
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
        userInfoProvider: UserInfoProvider = .mockAny()
    ) -> DatadogV1Context {
        DatadogV1Context(
            service: service,
            env: env,
            version: version,
            source: source,
            sdkVersion: sdkVersion,
            device: device,
            dateCorrector: dateCorrector,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            userInfoProvider: userInfoProvider
        )
    }

    init(_ v2: DatadogContext) {
        self.init(
            service: v2.service,
            env: v2.env,
            version: v2.version,
            source: v2.source,
            sdkVersion: v2.sdkVersion,
            device: v2.device,
            dateCorrector: DateCorrectorMock(offset: v2.serverTimeOffset),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: v2.networkConnectionInfo),
            carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: v2.carrierInfo),
            userInfoProvider: UserInfoProvider.mockWith(userInfo: v2.userInfo ?? .empty)
        )
    }
}
