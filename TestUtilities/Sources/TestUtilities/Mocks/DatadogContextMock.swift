/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@testable import Datadog

extension DatadogContext: AnyMockable {
    static func mockAny() -> DatadogContext { mockWith() }

    static func mockWith(
        site: DatadogSite? = .mockAny(),
        clientToken: String = .mockAny(),
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        variant: String? = nil,
        source: String = .mockAny(),
        sdkVersion: String = .mockAny(),
        ciAppOrigin: String? = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        applicationName: String = .mockAny(),
        applicationBundleIdentifier: String = .mockAny(),
        sdkInitDate: Date = Date(),
        device: DeviceInfo = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        trackingConsent: TrackingConsent = .pending,
        launchTime: LaunchTime = .mockAny(),
        applicationStateHistory: AppStateHistory = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockWith(reachability: .yes),
        carrierInfo: CarrierInfo? = .mockAny(),
        batteryStatus: BatteryStatus? = .mockAny(),
        isLowPowerModeEnabled: Bool = false,
        featuresAttributes: [String: FeatureBaggage] = [:]
    ) -> DatadogContext {
        .init(
            site: site,
            clientToken: clientToken,
            service: service,
            env: env,
            version: version,
            variant: variant,
            source: source,
            sdkVersion: sdkVersion,
            ciAppOrigin: ciAppOrigin,
            serverTimeOffset: serverTimeOffset,
            applicationName: applicationName,
            applicationBundleIdentifier: applicationBundleIdentifier,
            sdkInitDate: sdkInitDate,
            device: device,
            userInfo: userInfo,
            trackingConsent: trackingConsent,
            launchTime: launchTime,
            applicationStateHistory: applicationStateHistory,
            networkConnectionInfo: networkConnectionInfo,
            carrierInfo: carrierInfo,
            batteryStatus: batteryStatus,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            featuresAttributes: featuresAttributes
        )
    }

    static func mockRandom() -> DatadogContext {
        .init(
            site: .mockRandom(),
            clientToken: .mockRandom(),
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            variant: .mockRandom(),
            source: .mockAnySource(),
            sdkVersion: .mockRandom(),
            ciAppOrigin: .mockRandom(),
            serverTimeOffset: .mockRandomInThePast(),
            applicationName: .mockRandom(),
            applicationBundleIdentifier: .mockRandom(),
            sdkInitDate: .mockRandomInThePast(),
            device: .mockRandom(),
            userInfo: .mockRandom(),
            trackingConsent: .mockRandom(),
            launchTime: nil,
            applicationStateHistory: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            batteryStatus: nil,
            isLowPowerModeEnabled: .mockRandom(),
            featuresAttributes: .mockRandom()
        )
    }
}

extension Datadog.Configuration.DatadogEndpoint: AnyMockable, RandomMockable {
    static func mockAny() -> Datadog.Configuration.DatadogEndpoint {
        return .us1
    }

    static func mockRandom() -> Self {
        return [.us1, .us3, .eu1, .us1_fed].randomElement()!
    }
}

extension DeviceInfo {
    static func mockAny() -> DeviceInfo {
        return .mockWith()
    }

    static func mockWith(
        name: String = .mockAny(),
        model: String = .mockAny(),
        osName: String = .mockAny(),
        osVersion: String = .mockAny(),
        architecture: String = .mockAny()
    ) -> DeviceInfo {
        return .init(
            name: name,
            model: model,
            osName: osName,
            osVersion: osVersion,
            architecture: architecture
        )
    }

    static func mockRandom() -> DeviceInfo {
        return .init(
            name: .mockRandom(),
            model: .mockRandom(),
            osName: .mockRandom(),
            osVersion: .mockRandom(),
            architecture: .mockRandom()
        )
    }
}

extension UserInfo: AnyMockable, RandomMockable {
    static func mockAny() -> UserInfo {
        return mockEmpty()
    }

    static func mockEmpty() -> UserInfo {
        return UserInfo(id: nil, name: nil, email: nil, extraInfo: [:])
    }

    static func mockRandom() -> UserInfo {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension UserInfo: EquatableInTests {}

extension LaunchTime: AnyMockable {
    static func mockAny() -> LaunchTime {
        .init(
            launchTime: .mockAny(),
            launchDate: .mockAny(),
            isActivePrewarm: .mockAny()
        )
    }
}

extension AppStateHistory: AnyMockable {
    static func mockAny() -> Self {
        return mockAppInForeground(since: .mockDecember15th2019At10AMUTC())
    }

    static func mockAppInForeground(since date: Date = Date()) -> Self {
        return .init(initialSnapshot: .init(state: .active, date: date), recentDate: date)
    }

    static func mockAppInBackground(since date: Date = Date()) -> Self {
        return .init(initialSnapshot: .init(state: .background, date: date), recentDate: date)
    }

    static func mockRandom(since date: Date = Date()) -> Self {
        return Bool.random() ? mockAppInForeground(since: date) : mockAppInBackground(since: date)
    }
}

extension NetworkConnectionInfo: RandomMockable {
    static func mockAny() -> NetworkConnectionInfo {
        return mockWith()
    }

    static func mockWith(
        reachability: NetworkConnectionInfo.Reachability = .mockAny(),
        availableInterfaces: [NetworkConnectionInfo.Interface] = [.wifi],
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        isExpensive: Bool = true,
        isConstrained: Bool = true
    ) -> NetworkConnectionInfo {
        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    static func mockRandom() -> NetworkConnectionInfo {
        return NetworkConnectionInfo(
            reachability: .mockRandom(),
            availableInterfaces: .mockRandom(),
            supportsIPv4: .random(),
            supportsIPv6: .random(),
            isExpensive: .random(),
            isConstrained: .random()
        )
    }
}

extension NetworkConnectionInfo.Interface: RandomMockable {
    static func mockRandom() -> NetworkConnectionInfo.Interface {
        return allCases.randomElement()!
    }
}

extension CarrierInfo: RandomMockable {
    static func mockAny() -> CarrierInfo {
        return mockWith()
    }

    static func mockWith(
        carrierName: String? = .mockAny(),
        carrierISOCountryCode: String? = .mockAny(),
        carrierAllowsVOIP: Bool = .mockAny(),
        radioAccessTechnology: CarrierInfo.RadioAccessTechnology = .mockAny()
    ) -> CarrierInfo {
        return CarrierInfo(
            carrierName: carrierName,
            carrierISOCountryCode: carrierISOCountryCode,
            carrierAllowsVOIP: carrierAllowsVOIP,
            radioAccessTechnology: radioAccessTechnology
        )
    }

    static func mockRandom() -> CarrierInfo {
        return CarrierInfo(
            carrierName: .mockRandom(),
            carrierISOCountryCode: .mockRandom(),
            carrierAllowsVOIP: .random(),
            radioAccessTechnology: .mockRandom()
        )
    }
}

extension CarrierInfo.RadioAccessTechnology: RandomMockable {
    static func mockAny() -> CarrierInfo.RadioAccessTechnology { .LTE }

    static func mockRandom() -> CarrierInfo.RadioAccessTechnology {
        return allCases.randomElement()!
    }
}

extension BatteryStatus {
    static func mockAny() -> BatteryStatus {
        return mockWith()
    }

    static func mockWith(
        state: State = .charging,
        level: Float = 0.5
    ) -> BatteryStatus {
        return BatteryStatus(state: state, level: level)
    }
}

extension TrackingConsent {
    static func mockRandom() -> TrackingConsent {
        return [.granted, .notGranted, .pending].randomElement()!
    }

    static func mockRandom(otherThan consent: TrackingConsent? = nil) -> TrackingConsent {
        while true {
            let randomConsent: TrackingConsent = .mockRandom()
            if randomConsent != consent {
                return randomConsent
            }
        }
    }
}

extension String {
    static func mockAnySource() -> String {
        return ["ios", "android", "browser", "ios", "react-native", "flutter"].randomElement()!
    }
}

extension NetworkConnectionInfo.Reachability {
    static func mockAny() -> NetworkConnectionInfo.Reachability {
        return .maybe
    }

    static func mockRandom(
        within cases: [NetworkConnectionInfo.Reachability] = [.yes, .no, .maybe]
    ) -> NetworkConnectionInfo.Reachability {
        return cases.randomElement()!
    }
}
