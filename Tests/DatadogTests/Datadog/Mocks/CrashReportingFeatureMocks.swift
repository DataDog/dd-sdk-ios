/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import Datadog

extension CrashReporter {
    /// Mocks the Crash Reporting feature instance which doesn't load crash reports.
    static func mockNoOp(
            core: DatadogCoreProtocol = NOPDatadogCore(),
            crashReportingPlugin: DDCrashReportingPluginType = NoopCrashReportingPlugin()
    ) -> CrashReporter {
        return .mockWith(
            loggingOrRUMIntegration: CrashReportingWithRUMIntegration.mockWith(core: core),
            crashReportingPlugin: crashReportingPlugin
        )
    }

    static func mockWith(
        loggingOrRUMIntegration: CrashReportingIntegration,
        crashReportingPlugin: DDCrashReportingPluginType = NoopCrashReportingPlugin(),
        crashContextProvider: CrashContextProviderType = CrashContextProviderMock(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) -> CrashReporter {
        .init(
            crashReportingPlugin: crashReportingPlugin,
            crashContextProvider: crashContextProvider,
            loggingOrRUMIntegration: loggingOrRUMIntegration,
            messageReceiver: messageReceiver
        )
    }
}

internal class CrashReportingPluginMock: DDCrashReportingPluginType {
    /// The crash report loaded by this plugin.
    var pendingCrashReport: DDCrashReport?
    /// If the plugin was asked to delete the crash report.
    var hasPurgedCrashReport: Bool?
    /// Custom app state data injected to the plugin.
    var injectedContextData: Data?

    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        hasPurgedCrashReport = completion(pendingCrashReport)
        didReadPendingCrashReport?()
    }

    /// Notifies the `readPendingCrashReport(completion:)` return.
    var didReadPendingCrashReport: (() -> Void)?

    func inject(context: Data) {
        injectedContextData = context
        didInjectContext?()
    }

    /// Notifies the `inject(context:)` return.
    var didInjectContext: (() -> Void)?
}

internal class NoopCrashReportingPlugin: DDCrashReportingPluginType {
    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {}
    func inject(context: Data) {}
}

internal class CrashContextProviderMock: CrashContextProviderType {
    private(set) var currentCrashContext: CrashContext?
    var onCrashContextChange: (CrashContext) -> Void

    init(initialCrashContext: CrashContext = .mockAny()) {
        self.currentCrashContext = initialCrashContext
        self.onCrashContextChange = { _ in }
    }
}

class CrashReportingIntegrationMock: CrashReportingIntegration {
    var sentCrashReport: DDCrashReport?
    var sentCrashContext: CrashContext?

    func send(report: DDCrashReport, with context: CrashContext) {
        sentCrashReport = report
        sentCrashContext = context
        didSendCrashReport?()
    }

    var didSendCrashReport: (() -> Void)?
}

extension CrashContext: EquatableInTests {}

extension CrashContext {
    static func mockAny() -> CrashContext {
        return mockWith()
    }

    static func mockWith(
        serverTimeOffset: TimeInterval = .zero,
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        device: DeviceInfo = .mockAny(),
        sdkVersion: String = .mockAny(),
        source: String = .mockAny(),
        trackingConsent: TrackingConsent = .granted,
        userInfo: UserInfo? = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        carrierInfo: CarrierInfo? = .mockAny(),
        lastRUMViewEvent: RUMViewEvent? = nil,
        lastRUMSessionState: RUMSessionState? = .mockAny(),
        lastIsAppInForeground: Bool = .mockAny()
    ) -> Self {
        .init(
            serverTimeOffset: serverTimeOffset,
            service: service,
            env: env,
            version: version,
            device: device,
            sdkVersion: service,
            source: source,
            trackingConsent: trackingConsent,
            userInfo: userInfo,
            networkConnectionInfo: networkConnectionInfo,
            carrierInfo: carrierInfo,
            lastRUMViewEvent: lastRUMViewEvent,
            lastRUMSessionState: lastRUMSessionState,
            lastIsAppInForeground: lastIsAppInForeground
        )
    }

    static func mockRandom() -> Self {
        .init(
            serverTimeOffset: .zero,
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            device: .mockRandom(),
            sdkVersion: .mockRandom(),
            source: .mockRandom(),
            trackingConsent: .granted,
            userInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastRUMViewEvent: nil,
            lastRUMSessionState: .mockRandom(),
            lastIsAppInForeground: .mockRandom()
        )
    }

    var data: Data { try! JSONEncoder().encode(self) }
}

extension DDCrashReport: EquatableInTests {}
extension DDCrashReport.Thread: EquatableInTests {}
extension DDCrashReport.BinaryImage: EquatableInTests {}
extension DDCrashReport.Meta: EquatableInTests {}

internal extension DDCrashReport {
    static func mockAny() -> DDCrashReport {
        return .mockWith()
    }

    static func mockWith(
        date: Date? = .mockAny(),
        type: String = .mockAny(),
        message: String = .mockAny(),
        stack: String = .mockAny(),
        threads: [Thread] = [],
        binaryImages: [BinaryImage] = [],
        meta: Meta = .mockAny(),
        wasTruncated: Bool = .mockAny(),
        context: Data? = .mockAny()
    ) -> DDCrashReport {
        return DDCrashReport(
            date: date,
            type: type,
            message: message,
            stack: stack,
            threads: threads,
            binaryImages: binaryImages,
            meta: meta,
            wasTruncated: wasTruncated,
            context: context
        )
    }

    static func mockRandomWith(context: CrashContext) -> DDCrashReport {
        return mockWith(
            date: .mockRandomInThePast(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            context: context.data
        )
    }
}

internal extension DDCrashReport.Meta {
    static func mockAny() -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: nil,
            processName: nil,
            parentProcess: nil,
            path: nil,
            codeType: nil,
            exceptionType: nil,
            exceptionCodes: nil
        )
    }
}

internal extension CrashReportingWithRUMIntegration {
    static func mockWith(
        core: DatadogCoreProtocol,
        applicationID: String = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        sessionSampler: Sampler = .mockKeepAll(),
        backgroundEventTrackingEnabled: Bool = true,
        uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator()
    ) -> Self {
        .init(
            core: core,
            applicationID: applicationID,
            dateProvider: dateProvider,
            sessionSampler: sessionSampler,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled,
            uuidGenerator: uuidGenerator
        )
    }
}
