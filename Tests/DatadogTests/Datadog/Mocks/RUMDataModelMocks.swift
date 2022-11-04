/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension RUMUser: EquatableInTests {}
extension RUMConnectivity: EquatableInTests {}
extension RUMViewEvent: EquatableInTests {}
extension RUMResourceEvent: EquatableInTests {}
extension RUMActionEvent: EquatableInTests {}
extension RUMErrorEvent: EquatableInTests {}
extension RUMLongTaskEvent: EquatableInTests {}
extension RUMCrashEvent: EquatableInTests {}
extension RUMDevice: EquatableInTests {}
extension RUMOperatingSystem: EquatableInTests {}

extension RUMUser {
    static func mockRandom() -> RUMUser {
        return RUMUser(
            email: .mockRandom(),
            id: .mockRandom(),
            name: .mockRandom(),
            usrInfo: mockRandomAttributes()
        )
    }
}

extension RUMConnectivity {
    static func mockRandom() -> RUMConnectivity {
        return RUMConnectivity(
            cellular: .init(
                carrierName: .mockRandom(),
                technology: .mockRandom()
            ),
            interfaces: [.bluetooth, .cellular].randomElements(),
            status: [.connected, .maybe, .notConnected].randomElement()!
        )
    }
}

extension RUMMethod: RandomMockable {
    static func mockRandom() -> RUMMethod {
        return [.post, .get, .head, .put, .delete, .patch].randomElement()!
    }
}

extension RUMEventAttributes: RandomMockable {
    static func mockRandom() -> RUMEventAttributes {
        return .init(contextInfo: mockRandomAttributes())
    }
}

extension RUMDevice: RandomMockable {
    static func mockRandom() -> RUMDevice {
        return .init(
            architecture: .mockRandom(),
            brand: .mockRandom(),
            model: .mockRandom(),
            name: .mockRandom(),
            type: .mockRandom()
        )
    }
}

extension RUMActionID: RandomMockable {
    static func mockRandom() -> RUMActionID {
        if Bool.random() {
            return .string(value: .mockRandom())
        } else {
            return .stringsArray(value: .mockRandom())
        }
    }
}

extension RUMActionID {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}

extension RUMDevice.RUMDeviceType: RandomMockable {
    static func mockRandom() -> RUMDevice.RUMDeviceType {
        return [.mobile, .desktop, .tablet, .tv, .gamingConsole, .bot, .other].randomElement()!
    }
}

extension RUMOperatingSystem: RandomMockable {
    static func mockRandom() -> RUMOperatingSystem {
        return .init(
            name: .mockRandom(length: 5),
            version: .mockRandom(among: .decimalDigits, length: 2),
            versionMajor: .mockRandom(among: .decimalDigits, length: 1)
        )
    }
}

extension RUMViewEvent: RandomMockable {
    static func mockRandom() -> RUMViewEvent {
        return mockRandomWith()
    }

    /// Produces random `RUMViewEvent` with setting given fields to certain values.
    static func mockRandomWith(
        viewIsActive: Bool? = .random(),
        viewTimeSpent: Int64 = .mockRandom()
    ) -> RUMViewEvent {
        return RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                documentVersion: .mockRandom(),
                session: .init(plan: .plan1)
            ),
            application: .init(id: .mockRandom()),
            ciTest: nil,
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(
                action: .init(count: .mockRandom()),
                cpuTicksCount: .mockRandom(),
                cpuTicksPerSecond: .mockRandom(),
                crash: .init(count: .mockRandom()),
                cumulativeLayoutShift: .mockRandom(),
                customTimings: .mockAny(),
                domComplete: .mockRandom(),
                domContentLoaded: .mockRandom(),
                domInteractive: .mockRandom(),
                error: .init(count: .mockRandom()),
                firstByte: .mockRandom(),
                firstContentfulPaint: .mockRandom(),
                firstInputDelay: .mockRandom(),
                firstInputTime: .mockRandom(),
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                frozenFrame: .init(count: .mockRandom()),
                frustration: nil,
                id: .mockRandom(),
                inForegroundPeriods: [
                    .init(
                        duration: .mockRandom(),
                        start: .mockRandom()
                    )
                ],
                isActive: viewIsActive,
                isSlowRendered: .mockRandom(),
                jsRefreshRate: nil,
                largestContentfulPaint: .mockRandom(),
                loadEvent: .mockRandom(),
                loadingTime: viewTimeSpent,
                loadingType: nil,
                longTask: .init(count: .mockRandom()),
                memoryAverage: .mockRandom(),
                memoryMax: .mockRandom(),
                name: .mockRandom(),
                referrer: .mockRandom(),
                refreshRateAverage: .mockRandom(),
                refreshRateMin: .mockRandom(),
                resource: .init(count: .mockRandom()),
                timeSpent: viewTimeSpent,
                url: .mockRandom()
            )
        )
    }
}

extension RUMResourceEvent: RandomMockable {
    static func mockRandom() -> RUMResourceEvent {
        return RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                discarded: nil,
                rulePsr: nil,
                session: .init(plan: .plan1),
                spanId: .mockRandom(),
                traceId: .mockRandom()
            ),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            ciTest: nil,
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            resource: .init(
                connect: .init(duration: .mockRandom(), start: .mockRandom()),
                dns: .init(duration: .mockRandom(), start: .mockRandom()),
                download: .init(duration: .mockRandom(), start: .mockRandom()),
                duration: .mockRandom(),
                firstByte: .init(duration: .mockRandom(), start: .mockRandom()),
                id: .mockRandom(),
                method: .mockRandom(),
                provider: .init(
                    domain: .mockRandom(),
                    name: .mockRandom(),
                    type: Bool.random() ? .firstParty : nil
                ),
                redirect: .init(duration: .mockRandom(), start: .mockRandom()),
                size: .mockRandom(),
                ssl: .init(duration: .mockRandom(), start: .mockRandom()),
                statusCode: .mockRandom(),
                type: [.native, .image].randomElement()!,
                url: .mockRandom()
            ),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(
                id: .mockRandom(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMActionEvent: RandomMockable {
    static func mockRandom() -> RUMActionEvent {
        return RUMActionEvent(
            dd: .init(
                action: .init(
                    position: nil,
                    target: .init(
                        height: nil,
                        selector: nil,
                        width: .mockRandom()
                    )
                ),
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: .init(
                crash: .init(count: .mockRandom()),
                error: .init(count: .mockRandom()),
                frustration: nil,
                id: .mockRandom(),
                loadingTime: .mockRandom(),
                longTask: .init(count: .mockRandom()),
                resource: .init(count: .mockRandom()),
                target: .init(name: .mockRandom()),
                type: [.tap, .swipe, .scroll].randomElement()!
            ),
            application: .init(id: .mockRandom()),
            ciTest: nil,
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(
                id: .mockRandom(),
                inForeground: .random(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMErrorEvent.Error.SourceType: RandomMockable {
    static func mockRandom() -> RUMErrorEvent.Error.SourceType {
        return [.android, .browser, .ios, .reactNative].randomElement()!
    }
}

extension RUMErrorEvent: RandomMockable {
    static func mockRandom() -> RUMErrorEvent {
        return RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            ciTest: nil,
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            error: .init(
                handling: nil,
                handlingStack: nil,
                id: .mockRandom(),
                isCrash: .random(),
                message: .mockRandom(),
                resource: .init(
                    method: .mockRandom(),
                    provider: .init(
                        domain: .mockRandom(),
                        name: .mockRandom(),
                        type: Bool.random() ? .firstParty : nil
                    ),
                    statusCode: .mockRandom(),
                    url: .mockRandom()
                ),
                source: [.source, .network, .custom].randomElement()!,
                sourceType: .mockRandom(),
                stack: .mockRandom(),
                type: .mockRandom()
            ),
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: .mockRandom(),
                type: .user
            ),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(
                id: .mockRandom(),
                inForeground: .random(),
                referrer: .mockRandom(),
                url: .mockRandom()
            )
        )
    }
}

extension RUMCrashEvent: RandomMockable {
    static func mockRandom(error: RUMErrorEvent) -> RUMCrashEvent {
        return .init(
            error: error,
            additionalAttributes: mockRandomAttributes()
        )
    }

    static func mockRandom() -> RUMCrashEvent {
        return mockRandom(error: .mockRandom())
    }
}

extension RUMLongTaskEvent: RandomMockable {
    static func mockRandom() -> RUMLongTaskEvent {
        return RUMLongTaskEvent(
            dd: .init(
                browserSdkVersion: nil,
                discarded: nil,
                session: .init(plan: .plan1)
            ),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            ciTest: nil,
            connectivity: .mockRandom(),
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            longTask: .init(duration: .mockRandom(), id: .mockRandom(), isFrozenFrame: .mockRandom()),
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(hasReplay: false, id: .mockRandom(), type: .user),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(id: .mockRandom(), name: .mockRandom(), referrer: .mockRandom(), url: .mockRandom())
        )
    }
}

extension TelemetryConfigurationEvent: EquatableInTests {
}

extension TelemetryConfigurationEvent: RandomMockable {
    static func mockRandom() -> TelemetryConfigurationEvent {
        return TelemetryConfigurationEvent(
            dd: .init(),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            date: .mockRandom(),
            experimentalFeatures: nil,
            service: .mockRandom(),
            session: .init(id: .mockRandom()),
            source: .ios,
            telemetry: .init(
                configuration: .init(
                    actionNameAttribute: nil,
                    batchSize: .mockAny(),
                    batchUploadFrequency: .mockAny(),
                    defaultPrivacyLevel: .mockAny(),
                    forwardConsoleLogs: nil,
                    forwardErrorsToLogs: nil,
                    forwardReports: nil,
                    initializationType: nil,
                    mobileVitalsUpdatePeriod: .mockRandom(),
                    premiumSampleRate: nil,
                    replaySampleRate: nil,
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: .mockRandom(),
                    silentMultipleInit: nil,
                    telemetryConfigurationSampleRate: .mockRandom(),
                    telemetrySampleRate: .mockRandom(),
                    traceSampleRate: .mockRandom(),
                    trackActions: .mockRandom(),
                    trackBackgroundEvents: .mockRandom(),
                    trackCrossPlatformLongTasks: .mockRandom(),
                    trackErrors: .mockRandom(),
                    trackFlutterPerformance: .mockRandom(),
                    trackFrustrations: .mockRandom(),
                    trackInteractions: .mockRandom(),
                    trackNativeErrors: .mockRandom(),
                    trackNativeLongTasks: .mockRandom(),
                    trackNativeViews: .mockRandom(),
                    trackNetworkRequests: .mockRandom(),
                    trackSessionAcrossSubdomains: nil,
                    trackViewsManually: nil,
                    useAllowedTracingOrigins: .mockRandom(),
                    useAttachToExisting: .mockRandom(),
                    useBeforeSend: nil,
                    useCrossSiteSessionCookie: nil,
                    useExcludedActivityUrls: nil,
                    useFirstPartyHosts: .mockRandom(),
                    useLocalEncryption: .mockRandom(),
                    useProxy: .mockRandom(),
                    useSecureSessionCookie: nil,
                    useTracing: .mockRandom(),
                    viewTrackingStrategy: nil
                )
            ),
            version: .mockAny(),
            view: .init(id: .mockRandom())
        )
    }
}

extension String {
    static func mockAnySource() -> String {
        return ["ios", "android", "browser", "ios", "react-native", "flutter"].randomElement()!
    }
}
