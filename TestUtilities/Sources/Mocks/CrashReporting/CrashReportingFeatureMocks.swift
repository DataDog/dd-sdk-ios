/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

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

public class CrashReportingPluginMock: CrashReportingPlugin {
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

    public func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        hasPurgedCrashReport = completion(pendingCrashReport)
        didReadPendingCrashReport?()
    }

    /// Notifies the `readPendingCrashReport(completion:)` return.
    public var didReadPendingCrashReport: (() -> Void)?

    public func inject(context: Data) {
        injectedContextData = context
        didInjectContext?()
    }

    /// Notifies the `inject(context:)` return.
    public var didInjectContext: (() -> Void)?

    public var backtraceReporter: BacktraceReporting? { injectedBacktraceReporter }
}

public class NOPCrashReportingPlugin: CrashReportingPlugin {
    public func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {}
    public func inject(context: Data) {}
    public var backtraceReporter: BacktraceReporting? { nil }

    public init() {}
}

public class CrashContextProviderMock: CrashContextProvider {
    public private(set) var currentCrashContext: CrashContext?
    public var onCrashContextChange: (CrashContext) -> Void

    public init(initialCrashContext: CrashContext = .mockAny()) {
        self.currentCrashContext = initialCrashContext
        self.onCrashContextChange = { _ in }
    }
}

public class CrashReportSenderMock: CrashReportSender {
    public var sentCrashReport: DDCrashReport?
    public var sentCrashContext: CrashContext?

    public init() {}

    public func send(report: DDCrashReport, with context: CrashContext) {
        sentCrashReport = report
        sentCrashContext = context
        didSendCrashReport?()
    }

    public var didSendCrashReport: (() -> Void)?

    public func send(launch: DatadogInternal.LaunchReport) {}
}

public class RUMCrashReceiverMock: FeatureMessageReceiver {
    public var receivedBaggage: FeatureBaggage?

    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .baggage(let label, let baggage) where label == CrashReportReceiver.MessageKeys.crash:
            receivedBaggage = baggage
            return true
        default:
            return false
        }
    }

    public init() {}
}

public class LogsCrashReceiverMock: FeatureMessageReceiver {
    public var receivedBaggage: FeatureBaggage?

    public init() {}

    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .baggage(let label, let baggage) where label == LoggingMessageKeys.crash:
            receivedBaggage = baggage
            return true
        default:
            return false
        }
    }
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
        device: DeviceInfo = .mockAny(),
        sdkVersion: String = .mockAny(),
        source: String = .mockAny(),
        trackingConsent: TrackingConsent = .granted,
        userInfo: UserInfo? = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny(),
        carrierInfo: CarrierInfo? = .mockAny(),
        lastRUMViewEvent: AnyCodable? = nil,
        lastRUMSessionState: AnyCodable? = nil,
        lastIsAppInForeground: Bool = .mockAny(),
        appLaunchDate: Date? = .mockRandomInThePast(),
        lastRUMAttributes: GlobalRUMAttributes? = nil,
        lastLogAttributes: AnyCodable? = nil
    ) -> Self {
        .init(
            serverTimeOffset: serverTimeOffset,
            service: service,
            env: env,
            version: version,
            buildNumber: buildNumber,
            device: device,
            sdkVersion: service,
            source: source,
            trackingConsent: trackingConsent,
            userInfo: userInfo,
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
            sdkVersion: .mockRandom(),
            source: .mockRandom(),
            trackingConsent: .granted,
            userInfo: .mockRandom(),
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastIsAppInForeground: .mockRandom(),
            appLaunchDate: .mockRandomInThePast(),
            lastRUMViewEvent: AnyCodable(mockRandomAttributes()),
            lastRUMSessionState: AnyCodable(mockRandomAttributes()),
            lastRUMAttributes: GlobalRUMAttributes(attributes: mockRandomAttributes()),
            lastLogAttributes: AnyCodable(mockRandomAttributes())
        )
    }

    public var data: Data { try! JSONEncoder.dd.default().encode(self) }
}
