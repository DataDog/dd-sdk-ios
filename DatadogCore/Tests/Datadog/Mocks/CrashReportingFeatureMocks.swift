/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogRUM
@testable import DatadogCrashReporting
@testable import DatadogCore

extension CrashReportingFeature {
    /// Mocks the Crash Reporting feature instance which doesn't load crash reports.
    static func mockNoOp(
            core: DatadogCoreProtocol = NOPDatadogCore(),
            crashReportingPlugin: CrashReportingPlugin = NOPCrashReportingPlugin()
    ) -> Self {
        return .mockWith(
            integration: MessageBusSender(core: core),
            crashReportingPlugin: crashReportingPlugin
        )
    }

    static func mockWith(
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

internal class CrashReportingPluginMock: CrashReportingPlugin {
    /// The crash report loaded by this plugin.
    var pendingCrashReport: DDCrashReport?
    /// If the plugin was asked to delete the crash report.
    @ReadWriteLock
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

internal class NOPCrashReportingPlugin: CrashReportingPlugin {
    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {}
    func inject(context: Data) {}
}

internal class CrashContextProviderMock: CrashContextProvider {
    private(set) var currentCrashContext: CrashContext?
    var onCrashContextChange: (CrashContext) -> Void

    init(initialCrashContext: CrashContext = .mockAny()) {
        self.currentCrashContext = initialCrashContext
        self.onCrashContextChange = { _ in }
    }
}

class CrashReportSenderMock: CrashReportSender {
    var sentCrashReport: DDCrashReport?
    var sentCrashContext: CrashContext?

    func send(report: DDCrashReport, with context: CrashContext) {
        sentCrashReport = report
        sentCrashContext = context
        didSendCrashReport?()
    }

    var didSendCrashReport: (() -> Void)?

    func send(launch: DatadogInternal.LaunchReport) {}
}

class RUMCrashReceiverMock: FeatureMessageReceiver {
    var receivedBaggage: FeatureBaggage?

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .baggage(let label, let baggage) where label == CrashReportReceiver.MessageKeys.crash:
            receivedBaggage = baggage
            return true
        default:
            return false
        }
    }
}

class LogsCrashReceiverMock: FeatureMessageReceiver {
    var receivedBaggage: FeatureBaggage?

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
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
    static func mockAny() -> CrashContext {
        return mockWith()
    }

    static func mockWith(
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

    static func mockRandom() -> Self {
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

    var data: Data { try! JSONEncoder.dd.default().encode(self) }
}

internal extension DDCrashReport {
    static func mockAny() -> DDCrashReport {
        return .mockWith()
    }

    static func mockWith(
        date: Date? = .mockAny(),
        type: String = .mockAny(),
        message: String = .mockAny(),
        stack: String = .mockAny(),
        threads: [DDThread] = [],
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
        return mockRandomWith(contextData: context.data)
    }

    static func mockRandomWith(contextData: Data) -> DDCrashReport {
        return mockWith(
            date: .mockRandomInThePast(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            context: contextData
        )
    }
}

internal extension DDCrashReport.Meta {
    static func mockAny() -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: nil,
            process: nil,
            parentProcess: nil,
            path: nil,
            codeType: nil,
            exceptionType: nil,
            exceptionCodes: nil
        )
    }
}
