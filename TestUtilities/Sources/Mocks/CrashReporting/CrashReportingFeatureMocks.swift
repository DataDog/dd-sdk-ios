/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogRUM
@testable import DatadogCrashReporting
@testable import DatadogCore

extension CrashReportingFeature {
    /// Mocks the Crash Reporting feature instance which doesn't load crash reports.
    public static func mockNoOp(
            core: DatadogCoreProtocol = NOPDatadogCore(),
            crashReportingPlugin: CrashReportingPlugin = NOPCrashReportingPlugin()
    ) -> Self {
        return .mockWith(
            integration: MessageBusSender(core: core),
            crashReportingPlugin: crashReportingPlugin
        )
    }

    public static func mockWith(
        integration: CrashReportSender,
        crashReportingPlugin: CrashReportingPlugin = NOPCrashReportingPlugin(),
        crashContextProvider: CrashContextProvider = CrashContextProviderMock(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver(),
        telemetry: Telemetry = NOPTelemetry()
    ) -> Self {
        .init(
            crashReportingPlugin: crashReportingPlugin,
            crashContextProvider: crashContextProvider,
            sender: integration,
            messageReceiver: messageReceiver,
            telemetry: telemetry
        )
    }
}

public class CrashReportingPluginMock: CrashReportingPlugin, @unchecked Sendable {
    /// The crash report loaded by this plugin.
    public var pendingCrashReport: DDCrashReport?
    /// If the plugin was asked to delete the crash report.
    @ReadWriteLock
    public var hasPurgedCrashReport: Bool?
    /// Custom app state data injected to the plugin.
    public var injectedContextData: Data?
    /// Custom backtrace reporter injected to the plugin.
    public var injectedBacktraceReporter: BacktraceReporting?

    public init() {}

    public func readPendingCrashReport() async -> DDCrashReport? {
        let report = pendingCrashReport
        didReadPendingCrashReport?()
        return report
    }

    public func deletePendingCrashReports() {
        hasPurgedCrashReport = true
        didDeletePendingCrashReports?()
    }

    /// Notifies when `readPendingCrashReport()` returns.
    public var didReadPendingCrashReport: (() -> Void)?

    /// Notifies when `deletePendingCrashReports()` is called.
    public var didDeletePendingCrashReports: (() -> Void)?

    public func inject(context: Data) {
        injectedContextData = context
        didInjectContext?()
    }

    /// Notifies the `inject(context:)` return.
    public var didInjectContext: (() -> Void)?

    public var backtraceReporter: BacktraceReporting? { injectedBacktraceReporter }
}

public class NOPCrashReportingPlugin: CrashReportingPlugin, @unchecked Sendable {
    public func readPendingCrashReport() async -> DDCrashReport? { nil }
    public func deletePendingCrashReports() {}
    public func inject(context: Data) {}
    public var backtraceReporter: BacktraceReporting? { nil }

    public init() {}
}

public class CrashContextProviderMock: CrashContextProvider {
    public private(set) var currentCrashContext: CrashContext?
    public var onCrashContextChange: @Sendable (CrashContext) -> Void

    public init(initialCrashContext: CrashContext? = .mockAny()) {
        self.currentCrashContext = initialCrashContext
        self.onCrashContextChange = { _ in }
    }
}

public class CrashReportSenderMock: CrashReportSender, @unchecked Sendable {
    public var sentCrashReport: DDCrashReport?
    public var sentCrashContext: CrashContext?
    public var sentLaunchReport: LaunchReport?

    public init() {}

    public func send(report: DDCrashReport, with context: CrashContext) {
        sentCrashReport = report
        sentCrashContext = context
        didSendCrashReport?()
    }

    public var didSendCrashReport: (() -> Void)?

    public func send(launch: DatadogInternal.LaunchReport) {
        sentLaunchReport = launch
        didSendLaunchReport?()
    }

    public var didSendLaunchReport: (() -> Void)?
}

public class CrashReceiverMock: FeatureMessageReceiver, @unchecked Sendable {
    public var receivedCrash: Crash?

    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(crash as Crash) = message else {
            return false
        }
        receivedCrash = crash
        return true
    }

    public init() {}
}

extension CrashContext {
    public static func mockAny() -> CrashContext {
        return mockWith()
    }

    public static func mockWith(
        serverTimeOffset: TimeInterval = .zero,
        service: String = .mockAny(),
        env: String = .mockAny(),
        version: String = .mockAny(),
        buildNumber: String = .mockAny(),
        device: Device = .mockAny(),
        os: OperatingSystem = .mockAny(),
        sdkVersion: String = .mockAny(),
        source: String = .mockAny(),
        trackingConsent: TrackingConsent = .granted,
        userInfo: UserInfo? = .mockAny(),
        accountInfo: AccountInfo? = nil,
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        carrierInfo: CarrierInfo? = .mockAny(),
        lastRUMViewEvent: RUMViewEvent? = nil,
        lastRUMSessionState: RUMSessionState? = nil,
        lastIsAppInForeground: Bool = .mockAny(),
        appLaunchDate: Date? = .mockRandomInThePast(),
        lastRUMAttributes: RUMEventAttributes? = nil,
        lastLogAttributes: LogEventAttributes? = nil
    ) -> Self {
        .init(
            serverTimeOffset: serverTimeOffset,
            service: service,
            env: env,
            version: version,
            buildNumber: buildNumber,
            device: device,
            os: os,
            sdkVersion: service,
            source: source,
            trackingConsent: trackingConsent,
            userInfo: userInfo,
            accountInfo: accountInfo,
            networkConnectionInfo: networkConnectionInfo,
            carrierInfo: carrierInfo,
            lastIsAppInForeground: lastIsAppInForeground,
            appLaunchDate: appLaunchDate,
            lastRUMViewEvent: lastRUMViewEvent,
            lastRUMSessionState: lastRUMSessionState,
            lastRUMAttributes: lastRUMAttributes,
            lastLogAttributes: lastLogAttributes
        )
    }

    public static func mockRandom() -> Self {
        .init(
            serverTimeOffset: .zero,
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            buildNumber: .mockRandom(),
            device: .mockRandom(),
            os: .mockRandom(),
            sdkVersion: .mockRandom(),
            source: .mockRandom(),
            trackingConsent: .granted,
            userInfo: .mockRandom(),
            accountInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastIsAppInForeground: .mockRandom(),
            appLaunchDate: .mockRandomInThePast(),
            lastRUMViewEvent: .mockRandom(),
            lastRUMSessionState: .mockRandom(),
            lastRUMAttributes: .mockRandom(),
            lastLogAttributes: .mockRandom()
        )
    }

    public var data: Data { try! JSONEncoder.dd.default().encode(self) }
}
