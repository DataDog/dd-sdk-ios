/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogInternal

extension DatadogContext: AnyMockable, RandomMockable {
    public static func mockAny() -> DatadogContext { mockWith() }

    public static func mockWith(
        site: DatadogSite = .mockAny(),
        clientToken: String = .mockAny(),
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        buildNumber: String = .mockAny(),
        buildId: String? = nil,
        variant: String? = nil,
        source: String = .mockAny(),
        sdkVersion: String = .mockAny(),
        ciAppOrigin: String? = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        applicationName: String = .mockAny(),
        applicationBundleIdentifier: String = .mockAny(),
        applicationBundleType: BundleType = .mockAny(),
        sdkInitDate: Date = Date(),
        nativeSourceOverride: String? = nil,
        device: DeviceInfo = .mockAny(),
        localeInfo: LocaleInfo = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        accountInfo: AccountInfo? = nil,
        trackingConsent: TrackingConsent = .pending,
        launchTime: LaunchTime = .mockAny(),
        applicationStateHistory: AppStateHistory = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockWith(reachability: .yes),
        carrierInfo: CarrierInfo? = .mockAny(),
        batteryStatus: BatteryStatus? = .mockAny(),
        isLowPowerModeEnabled: Bool = false,
        additionalContext: [AdditionalContext] = []
    ) -> DatadogContext {
        var context = DatadogContext(
            site: site,
            clientToken: clientToken,
            service: service,
            env: env,
            version: version,
            buildNumber: buildNumber,
            buildId: buildId,
            variant: variant,
            source: source,
            sdkVersion: sdkVersion,
            ciAppOrigin: ciAppOrigin,
            serverTimeOffset: serverTimeOffset,
            applicationName: applicationName,
            applicationBundleIdentifier: applicationBundleIdentifier,
            applicationBundleType: applicationBundleType,
            sdkInitDate: sdkInitDate,
            device: device,
            localeInfo: localeInfo,
            nativeSourceOverride: nativeSourceOverride,
            userInfo: userInfo,
            accountInfo: accountInfo,
            trackingConsent: trackingConsent,
            launchTime: launchTime,
            applicationStateHistory: applicationStateHistory,
            networkConnectionInfo: networkConnectionInfo,
            carrierInfo: carrierInfo,
            batteryStatus: batteryStatus,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )

        additionalContext.forEach { context.set(additionalContext: $0) }
        return context
    }

    public static func mockRandom() -> DatadogContext {
        .init(
            site: .mockRandom(),
            clientToken: .mockRandom(),
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            buildNumber: .mockRandom(),
            buildId: .mockRandom(),
            variant: .mockRandom(),
            source: .mockAnySource(),
            sdkVersion: .mockRandom(),
            ciAppOrigin: .mockRandom(),
            serverTimeOffset: .mockRandomInThePast(),
            applicationName: .mockRandom(),
            applicationBundleIdentifier: .mockRandom(),
            applicationBundleType: .mockRandom(),
            sdkInitDate: .mockRandomInThePast(),
            device: .mockRandom(),
            localeInfo: .mockRandom(),
            userInfo: .mockRandom(),
            accountInfo: .mockRandom(),
            trackingConsent: .mockRandom(),
            launchTime: .mockRandom(),
            applicationStateHistory: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            batteryStatus: nil,
            isLowPowerModeEnabled: .mockRandom()
        )
    }
}

extension DatadogSite: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .us1
    }

    public static func mockRandom() -> Self {
        return [.us1, .us3, .us5, .eu1, .ap1, .ap2, .us1_fed].randomElement()!
    }
}

extension BundleType: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .iOSApp
    }

    public static func mockRandom() -> Self {
        return [.iOSApp, .iOSAppExtension].randomElement()!
    }
}

extension LocaleInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> LocaleInfo {
        return .mockWith()
    }

    public static func mockWith(
        locales: [String] = ["en"],
        currentLocale: Locale = Locale(identifier: "en-US"),
        timeZone: TimeZone = TimeZone(identifier: "Europe/Paris")!
    ) -> LocaleInfo {
        return .init(
            locales: locales,
            currentLocale: currentLocale,
            timeZone: timeZone
        )
    }

    public static func mockRandom() -> LocaleInfo {
        return .init(
            locales: .mockRandom(),
            currentLocale: Locale(identifier: .mockRandom()),
            timeZone: TimeZone(identifier: .mockRandom()) ?? TimeZone.current
        )
    }
}

extension DeviceInfo {
    public static func mockAny() -> DeviceInfo {
        return .mockWith()
    }

    public static func mockWith(
        name: String = "iPhone",
        model: String = "iPhone10,1",
        osName: String = "iOS",
        osVersion: String = "15.4.1",
        osBuildNumber: String = "13D20",
        architecture: String = "arm64e",
        isSimulator: Bool = true,
        vendorId: String? = "xyz",
        isDebugging: Bool = false,
        systemBootTime: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> DeviceInfo {
        return .init(
            name: name,
            model: model,
            osName: osName,
            osVersion: osVersion,
            osBuildNumber: osBuildNumber,
            architecture: architecture,
            isSimulator: isSimulator,
            vendorId: vendorId,
            isDebugging: isDebugging,
            systemBootTime: systemBootTime
        )
    }

    public static func mockRandom() -> DeviceInfo {
        return .init(
            name: .mockRandom(),
            model: .mockRandom(),
            osName: .mockRandom(),
            osVersion: .mockRandom(),
            osBuildNumber: .mockRandom(),
            architecture: .mockRandom(),
            isSimulator: .mockRandom(),
            vendorId: .mockRandom(),
            isDebugging: .mockRandom(),
            systemBootTime: .mockRandom()
        )
    }
}

extension UserInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> UserInfo {
        return mockEmpty()
    }

    public static func mockEmpty() -> UserInfo {
        return UserInfo(id: nil, name: nil, email: nil, extraInfo: [:])
    }

    public static func mockRandom() -> UserInfo {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension AccountInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return mockRandom()
    }

    public static func mockRandom() -> Self {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension LaunchTime: AnyMockable, RandomMockable {
    public static func mockAny() -> LaunchTime {
        .init(
            launchTime: .mockAny(),
            launchDate: .mockAny(),
            isActivePrewarm: .mockAny()
        )
    }

    public static func mockWith(
        launchTime: TimeInterval? = 1,
        launchDate: Date = Date(),
        isActivePrewarm: Bool = false
    ) -> LaunchTime {
        .init(
            launchTime: launchTime,
            launchDate: launchDate,
            isActivePrewarm: isActivePrewarm
        )
    }

    public static func mockRandom() -> LaunchTime {
        return .init(
            launchTime: .mockRandom(),
            launchDate: .mockRandom(),
            isActivePrewarm: .mockRandom()
        )
    }
}

extension AppState: AnyMockable, RandomMockable {
    public static func mockAny() -> AppState {
        return .active
    }

    public static func mockRandom() -> AppState {
        return [.active, .inactive, .background].randomElement()!
    }

    public static func mockRandom(runningInForeground: Bool) -> AppState {
        return runningInForeground ? [.active, .inactive].randomElement()! : .background
    }
}

extension AppStateHistory: AnyMockable {
    public static func mockAny() -> Self {
        return mockAppInForeground(since: .mockDecember15th2019At10AMUTC())
    }

    public static func mockAppInForeground(since date: Date = Date()) -> Self {
        return .init(initialSnapshot: .init(state: .active, date: date), recentDate: date)
    }

    public static func mockAppInBackground(since date: Date = Date()) -> Self {
        return .init(initialSnapshot: .init(state: .background, date: date), recentDate: date)
    }

    public static func mockRandom(since date: Date = Date()) -> Self {
        return Bool.random() ? mockAppInForeground(since: date) : mockAppInBackground(since: date)
    }
}

extension NetworkConnectionInfo: RandomMockable {
    public static func mockAny() -> NetworkConnectionInfo {
        return mockWith()
    }

    public static func mockWith(
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

    public static func mockRandom() -> NetworkConnectionInfo {
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
    public static func mockRandom() -> NetworkConnectionInfo.Interface {
        return allCases.randomElement()!
    }
}

extension CarrierInfo: RandomMockable {
    public static func mockAny() -> CarrierInfo {
        return mockWith()
    }

    public static func mockWith(
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

    public static func mockRandom() -> CarrierInfo {
        return CarrierInfo(
            carrierName: .mockRandom(),
            carrierISOCountryCode: .mockRandom(),
            carrierAllowsVOIP: .random(),
            radioAccessTechnology: .mockRandom()
        )
    }
}

extension CarrierInfo.RadioAccessTechnology: RandomMockable {
    public static func mockAny() -> CarrierInfo.RadioAccessTechnology { .LTE }

    public static func mockRandom() -> CarrierInfo.RadioAccessTechnology {
        return allCases.randomElement()!
    }
}

extension BatteryStatus: AnyMockable, RandomMockable {
    public static func mockAny() -> BatteryStatus {
        return mockWith()
    }

    public static func mockWith(
        state: State = .charging,
        level: Float = 0.5
    ) -> BatteryStatus {
        return BatteryStatus(state: state, level: level)
    }

    public static func mockRandom() -> BatteryStatus {
        return BatteryStatus(
            state: [.unknown, .unplugged, .charging, .full].randomElement() ?? .unknown,
            level: Float.random(in: 0.0...1.0)
        )
    }
}

//extension BrightnessLevel: AnyMockable, RandomMockable {
//    public static func mockAny() -> BrightnessLevel {
//        return mockWith()
//    }
//
//    public static func mockWith(
//        level: Float = 0.5
//    ) -> BrightnessLevel {
//        return level
//    }
//
//    public static func mockRandom() -> BrightnessLevel {
//        return Float.random(in: 0.0...1.0)
//    }
//}

extension TrackingConsent {
    public static func mockRandom() -> TrackingConsent {
        return [.granted, .notGranted, .pending].randomElement()!
    }

    public static func mockRandom(otherThan consent: TrackingConsent? = nil) -> TrackingConsent {
        while true {
            let randomConsent: TrackingConsent = .mockRandom()
            if randomConsent != consent {
                return randomConsent
            }
        }
    }
}

extension String {
    public static func mockAnySource() -> String {
        return ["ios", "android", "browser", "ios", "react-native", "flutter", "unity", "kotlin-multiplatform"].randomElement()!
    }

    public static func mockAnySourceType() -> String {
        return ["ios", "android", "browser", "react-native", "flutter", "roku", "ndk", "ios+il2cpp", "ndk+il2cpp"].randomElement()!
    }
}

extension NetworkConnectionInfo.Reachability {
    public static func mockAny() -> NetworkConnectionInfo.Reachability {
        return .maybe
    }

    public static func mockRandom(
        within cases: [NetworkConnectionInfo.Reachability] = [.yes, .no, .maybe]
    ) -> NetworkConnectionInfo.Reachability {
        return cases.randomElement()!
    }
}
