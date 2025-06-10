/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUMSessionState: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMSessionState {
        return mockWith()
    }

    public static func mockRandom() -> RUMSessionState {
        return .init(
            sessionUUID: .mockRandom(),
            isInitialSession: .mockRandom(),
            hasTrackedAnyView: .mockRandom(),
            didStartWithReplay: .mockRandom()
        )
    }

    public static func mockWith(
        sessionUUID: UUID = .mockAny(),
        isInitialSession: Bool = .mockAny(),
        hasTrackedAnyView: Bool = .mockAny(),
        didStartWithReplay: Bool? = .mockAny()
    ) -> RUMSessionState {
        return RUMSessionState(
            sessionUUID: sessionUUID,
            isInitialSession: isInitialSession,
            hasTrackedAnyView: hasTrackedAnyView,
            didStartWithReplay: didStartWithReplay
        )
    }
}

/// Creates random RUM event.
public func randomRUMEvent() -> RUMDataModel {
    // swiftlint:disable opening_brace
    return oneOf([
        { RUMViewEvent.mockRandom() },
        { RUMActionEvent.mockAny() },
        { RUMResourceEvent.mockRandom() },
        { RUMErrorEvent.mockRandom() },
        { RUMLongTaskEvent.mockRandom() },
    ])
    // swiftlint:enable opening_brace
}

extension RUMUser: RandomMockable {
    public static func mockRandom() -> RUMUser {
        return RUMUser(
            anonymousId: .mockRandom(),
            email: .mockRandom(),
            id: .mockRandom(),
            name: .mockRandom(),
            usrInfo: mockRandomAttributes()
        )
    }
}

extension RUMAccount: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            accountInfo: mockRandomAttributes()
        )
    }
}

extension RUMConnectivity: RandomMockable {
    public static func mockRandom() -> RUMConnectivity {
        return RUMConnectivity(
            cellular: .init(
                carrierName: .mockRandom(),
                technology: .mockRandom()
            ),
            effectiveType: nil,
            interfaces: [.bluetooth, .cellular].randomElements(),
            status: [.connected, .maybe, .notConnected].randomElement()!
        )
    }
}

extension RUMMethod: RandomMockable {
    public static func mockRandom() -> RUMMethod {
        return [.post, .get, .head, .put, .delete, .patch].randomElement()!
    }
}

extension RUMSessionPrecondition: RandomMockable {
    public static func mockRandom() -> RUMSessionPrecondition {
        return [.userAppLaunch, .inactivityTimeout, .maxDuration, .backgroundLaunch, .prewarm, .fromNonInteractiveSession, .explicitStop].randomElement()!
    }
}

extension RUMEventAttributes: RandomMockable {
    public static func mockRandom() -> RUMEventAttributes {
        return .init(contextInfo: mockRandomAttributes())
    }
}

extension RUMDevice: RandomMockable {
    public static func mockRandom() -> RUMDevice {
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
    public static func mockRandom() -> RUMActionID {
        if Bool.random() {
            return .string(value: .mockRandom())
        } else {
            return .stringsArray(value: .mockRandom())
        }
    }
}

extension RUMActionID {
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }
}

extension RUMDevice.RUMDeviceType: RandomMockable {
    public static func mockRandom() -> RUMDevice.RUMDeviceType {
        return [.mobile, .desktop, .tablet, .tv, .gamingConsole, .bot, .other].randomElement()!
    }
}

extension RUMOperatingSystem: RandomMockable {
    public static func mockRandom() -> RUMOperatingSystem {
        return .init(
            build: nil,
            name: .mockRandom(length: 5),
            version: .mockRandom(among: .decimalDigits, length: 2),
            versionMajor: .mockRandom(among: .decimalDigits, length: 1)
        )
    }
}

extension RUMViewEvent.DD.Configuration: RandomMockable {
    public static func mockRandom() -> RUMViewEvent.DD.Configuration {
        return .init(
            sessionReplaySampleRate: .mockRandom(min: 0, max: 100),
            sessionSampleRate: .mockRandom(min: 0, max: 100),
            startSessionReplayRecordingManually: nil
        )
    }
}

extension RUMViewEvent.View.SlowFrames: RandomMockable {
    public static func mockRandom() -> RUMViewEvent.View.SlowFrames {
        .init(duration: .mockRandom(), start: .mockRandom())
    }
}

extension RUMViewEvent: RandomMockable {
    public static func mockRandom() -> RUMViewEvent {
        return mockRandomWith()
    }

    /// Produces random `RUMViewEvent` with setting given fields to certain values.
    public static func mockRandomWith(
        sessionID: UUID = .mockRandom(),
        viewID: String = .mockRandom(),
        date: Int64 = .mockRandom(),
        viewIsActive: Bool? = .random(),
        viewTimeSpent: Int64 = .mockRandom(),
        viewURL: String = .mockRandom(),
        crashCount: Int64? = nil,
        hasReplay: Bool? = nil
    ) -> RUMViewEvent {
        return RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                cls: nil,
                configuration: .mockRandom(),
                documentVersion: .mockRandom(),
                pageStates: nil,
                replayStats: nil,
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: .mockRandom()
                )
            ),
            account: .mockRandom(),
            application: .init(id: .mockRandom()),
            buildId: nil,
            buildVersion: .mockRandom(),
            ciTest: nil,
            connectivity: .mockRandom(),
            container: nil,
            context: .mockRandom(),
            date: date,
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            privacy: nil,
            service: .mockRandom(),
            session: .init(
                hasReplay: hasReplay,
                id: sessionID.uuidString.lowercased(),
                isActive: true,
                sampledForReplay: nil,
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
                crash: crashCount.map { .init(count: $0) },
                cumulativeLayoutShift: .mockRandom(),
                cumulativeLayoutShiftTargetSelector: nil,
                cumulativeLayoutShiftTime: .mockRandom(),
                customTimings: .mockAny(),
                domComplete: .mockRandom(),
                domContentLoaded: .mockRandom(),
                domInteractive: .mockRandom(),
                error: .init(count: .mockRandom()),
                firstByte: .mockRandom(),
                firstContentfulPaint: .mockRandom(),
                firstInputDelay: .mockRandom(),
                firstInputTargetSelector: nil,
                firstInputTime: .mockRandom(),
                flutterBuildTime: nil,
                flutterRasterTime: nil,
                freezeRate: nil,
                frozenFrame: .init(count: .mockRandom()),
                frustration: nil,
                id: viewID,
                inForegroundPeriods: [
                    .init(
                        duration: .mockRandom(),
                        start: .mockRandom()
                    )
                ],
                interactionToNextPaint: nil,
                interactionToNextPaintTargetSelector: nil,
                interactionToNextPaintTime: .mockRandom(),
                interactionToNextViewTime: .mockRandom(),
                isActive: viewIsActive,
                isSlowRendered: .mockRandom(),
                jsRefreshRate: nil,
                largestContentfulPaint: .mockRandom(),
                largestContentfulPaintTargetSelector: nil,
                loadEvent: .mockRandom(),
                loadingTime: viewTimeSpent,
                loadingType: nil,
                longTask: .init(count: .mockRandom()),
                memoryAverage: .mockRandom(),
                memoryMax: .mockRandom(),
                name: .mockRandom(),
                networkSettledTime: .mockRandom(),
                referrer: .mockRandom(),
                refreshRateAverage: .mockRandom(),
                refreshRateMin: .mockRandom(),
                resource: .init(count: .mockRandom()),
                slowFrames: .mockRandom(),
                slowFramesRate: .mockRandom(),
                timeSpent: viewTimeSpent,
                url: viewURL
            )
        )
    }
}

extension RUMResourceEvent.DD.Configuration: RandomMockable {
    public static func mockRandom() -> RUMResourceEvent.DD.Configuration {
        .init(sessionReplaySampleRate: .mockRandom(min: 0, max: 100), sessionSampleRate: .mockRandom(min: 0, max: 100))
    }
}

extension RUMResourceEvent: RandomMockable {
    public static func mockRandom() -> RUMResourceEvent {
        return RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .mockRandom(),
                discarded: nil,
                rulePsr: nil,
                session: .init(
                    plan: [.plan1, .plan2].randomElement()!,
                    sessionPrecondition: .mockRandom()
                ),
                spanId: .mockRandom(),
                traceId: .mockRandom()
            ),
            account: .mockRandom(),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            buildId: nil,
            buildVersion: .mockRandom(),
            ciTest: nil,
            connectivity: .mockRandom(),
            container: nil,
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            resource: .init(
                connect: .init(duration: .mockRandom(), start: .mockRandom()),
                decodedBodySize: nil,
                deliveryType: nil,
                dns: .init(duration: .mockRandom(), start: .mockRandom()),
                download: .init(duration: .mockRandom(), start: .mockRandom()),
                duration: .mockRandom(),
                encodedBodySize: nil,
                firstByte: .init(duration: .mockRandom(), start: .mockRandom()),
                id: .mockRandom(),
                method: .mockRandom(),
                protocol: nil,
                provider: .init(
                    domain: .mockRandom(),
                    name: .mockRandom(),
                    type: Bool.random() ? .firstParty : nil
                ),
                redirect: .init(duration: .mockRandom(), start: .mockRandom()),
                renderBlockingStatus: nil,
                size: .mockRandom(),
                ssl: .init(duration: .mockRandom(), start: .mockRandom()),
                statusCode: .mockRandom(),
                transferSize: nil,
                type: [.native, .image].randomElement()!,
                url: .mockRandom(),
                worker: nil
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

extension RUMActionEvent.DD.Configuration: RandomMockable {
    public static func mockRandom() -> RUMActionEvent.DD.Configuration {
        .init(sessionReplaySampleRate: .mockRandom(min: 0, max: 100), sessionSampleRate: .mockRandom(min: 0, max: 100))
    }
}

extension RUMActionEvent: AnyMockable {
    public static func mockAny() -> RUMActionEvent {
        .mockWith()
    }

    public static func mockWith(
        sessionID: UUID = .mockRandom()
    ) -> RUMActionEvent {
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
                configuration: .mockRandom(),
                session: .init(
                    plan: [.plan1, .plan2].randomElement()!,
                    sessionPrecondition: .mockRandom()
                )
            ),
            account: .mockRandom(),
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
            buildId: nil,
            buildVersion: .mockRandom(),
            ciTest: nil,
            connectivity: .mockRandom(),
            container: nil,
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: nil,
                id: sessionID.uuidString.lowercased(),
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
    public static func mockRandom() -> RUMErrorEvent.Error.SourceType {
        return [.android, .browser, .ios, .reactNative].randomElement()!
    }
}

extension RUMErrorEvent.DD.Configuration: RandomMockable {
    public static func mockRandom() -> RUMErrorEvent.DD.Configuration {
        .init(sessionReplaySampleRate: .mockRandom(min: 0, max: 100), sessionSampleRate: .mockRandom(min: 0, max: 100))
    }
}

extension RUMErrorEvent: RandomMockable {
    public static func mockRandom() -> RUMErrorEvent {
        return RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .mockRandom(),
                session: .init(
                    plan: [.plan1, .plan2].randomElement()!,
                    sessionPrecondition: .mockRandom()
                )
            ),
            account: .mockRandom(),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            buildId: nil,
            buildVersion: .mockRandom(),
            ciTest: nil,
            connectivity: .mockRandom(),
            container: nil,
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            error: .init(
                binaryImages: nil,
                category: nil,
                csp: nil,
                handling: nil,
                handlingStack: nil,
                id: .mockRandom(),
                isCrash: .random(),
                message: .mockRandom(),
                meta: nil,
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
                threads: nil,
                timeSinceAppStart: nil,
                type: .mockRandom(),
                wasTruncated: .mockRandom()
            ),
            freeze: nil,
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

extension RUMLongTaskEvent.DD.Configuration: RandomMockable {
    public static func mockRandom() -> RUMLongTaskEvent.DD.Configuration {
        return .init(sessionReplaySampleRate: .mockRandom(min: 0, max: 100), sessionSampleRate: .mockRandom(min: 0, max: 100))
    }
}

extension RUMLongTaskEvent: RandomMockable {
    public static func mockRandom() -> RUMLongTaskEvent {
        return RUMLongTaskEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .mockRandom(),
                discarded: nil,
                session: .init(
                    plan: [.plan1, .plan2].randomElement()!,
                    sessionPrecondition: .mockRandom()
                )
            ),
            account: .mockRandom(),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            buildId: nil,
            buildVersion: .mockRandom(),
            ciTest: nil,
            connectivity: .mockRandom(),
            container: nil,
            context: .mockRandom(),
            date: .mockRandom(),
            device: .mockRandom(),
            display: nil,
            longTask: .init(
                blockingDuration: nil,
                duration: .mockRandom(),
                entryType: nil,
                firstUiEventTimestamp: nil,
                id: .mockRandom(),
                isFrozenFrame: .mockRandom(),
                renderStart: nil,
                scripts: nil,
                startTime: nil,
                styleAndLayoutStart: nil
            ),
            os: .mockRandom(),
            service: .mockRandom(),
            session: .init(
                hasReplay: false,
                id: .mockRandom(),
                type: .user
            ),
            source: .ios,
            synthetics: nil,
            usr: .mockRandom(),
            version: .mockAny(),
            view: .init(id: .mockRandom(), name: .mockRandom(), referrer: .mockRandom(), url: .mockRandom())
        )
    }
}

extension TelemetryConfigurationEvent: RandomMockable {
    public static func mockRandom() -> TelemetryConfigurationEvent {
        return TelemetryConfigurationEvent(
            dd: .init(),
            action: .init(id: .mockRandom()),
            application: .init(id: .mockRandom()),
            date: .mockRandom(),
            effectiveSampleRate: .mockRandom(),
            experimentalFeatures: nil,
            service: .mockRandom(),
            session: .init(id: .mockRandom()),
            source: .ios,
            telemetry: .init(
                configuration: .init(
                    actionNameAttribute: nil,
                    allowFallbackToLocalStorage: nil,
                    allowUntrustedEvents: nil,
                    appHangThreshold: .mockRandom(),
                    backgroundTasksEnabled: .mockRandom(),
                    batchProcessingLevel: .mockRandom(),
                    batchSize: .mockAny(),
                    batchUploadFrequency: .mockAny(),
                    compressIntakeRequests: nil,
                    defaultPrivacyLevel: .mockAny(),
                    forwardConsoleLogs: nil,
                    forwardErrorsToLogs: nil,
                    forwardReports: nil,
                    initializationType: nil,
                    invTimeThresholdMs: nil,
                    isMainProcess: nil,
                    mobileVitalsUpdatePeriod: .mockRandom(),
                    premiumSampleRate: nil,
                    reactNativeVersion: nil,
                    reactVersion: nil,
                    replaySampleRate: nil,
                    selectedTracingPropagators: nil,
                    sessionPersistence: nil,
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: .mockRandom(),
                    silentMultipleInit: nil,
                    storeContextsAcrossPages: nil,
                    telemetryConfigurationSampleRate: .mockRandom(),
                    telemetrySampleRate: .mockRandom(),
                    telemetryUsageSampleRate: nil,
                    tnsTimeThresholdMs: nil,
                    traceSampleRate: .mockRandom(),
                    trackBackgroundEvents: .mockRandom(),
                    trackCrossPlatformLongTasks: .mockRandom(),
                    trackErrors: .mockRandom(),
                    trackFeatureFlagsForEvents: nil,
                    trackFlutterPerformance: .mockRandom(),
                    trackFrustrations: .mockRandom(),
                    trackInteractions: .mockRandom(),
                    trackLongTask: .mockRandom(),
                    trackNativeErrors: .mockRandom(),
                    trackNativeLongTasks: .mockRandom(),
                    trackNativeViews: .mockRandom(),
                    trackNetworkRequests: .mockRandom(),
                    trackResources: .mockRandom(),
                    trackSessionAcrossSubdomains: nil,
                    trackViewsManually: nil,
                    trackingConsent: nil,
                    useAllowedTracingOrigins: .mockRandom(),
                    useAllowedTracingUrls: nil,
                    useBeforeSend: nil,
                    useCrossSiteSessionCookie: nil,
                    useExcludedActivityUrls: nil,
                    useFirstPartyHosts: .mockRandom(),
                    useLocalEncryption: .mockRandom(),
                    usePartitionedCrossSiteSessionCookie: .mockRandom(),
                    useProxy: .mockRandom(),
                    useSecureSessionCookie: nil,
                    useTracing: .mockRandom(),
                    useWorkerUrl: nil,
                    viewTrackingStrategy: nil
                ),
                device: .mockRandom(),
                os: .mockRandom(),
                telemetryInfo: [:]
            ),
            version: .mockAny(),
            view: .init(id: .mockRandom())
        )
    }
}

extension RUMTelemetryDevice: RandomMockable {
    public static func mockRandom() -> RUMTelemetryDevice {
        return RUMTelemetryDevice(
            architecture: .mockRandom(),
            brand: .mockRandom(),
            model: .mockRandom()
        )
    }
}

extension RUMTelemetryOperatingSystem: RandomMockable {
    public static func mockRandom() -> RUMTelemetryOperatingSystem {
        return RUMTelemetryOperatingSystem(
            build: .mockRandom(),
            name: .mockRandom(),
            version: .mockRandom()
        )
    }
}
