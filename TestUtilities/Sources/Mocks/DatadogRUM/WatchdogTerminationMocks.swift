/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

extension AppStateInfo: RandomMockable, AnyMockable {
    public static func mockAny() -> AppStateInfo {
        .init(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            appLaunchTime: .mockAny(),
            isDebugging: .mockAny(),
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: .mockAny()
        )
    }

    public static func mockRandom() -> AppStateInfo {
        .init(
            appVersion: .mockRandom(),
            osVersion: .mockRandom(),
            systemBootTime: .mockRandom(),
            appLaunchTime: .mockAny(),
            isDebugging: .mockRandom(),
            wasTerminated: .mockRandom(),
            isActive: .mockRandom(),
            vendorId: .mockRandom(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: .mockRandom()
        )
    }

    public static func mockWith(
        appVersion: String = .mockAny(),
        osVersion: String = .mockAny(),
        systemBootTime: TimeInterval = .mockAny(),
        appLaunchTime: TimeInterval = .mockAny(),
        isDebugging: Bool = .mockAny(),
        wasTerminated: Bool = .mockAny(),
        isActive: Bool = .mockAny(),
        vendorId: String? = .mockAny(),
        processId: UUID = .mockAny(),
        trackingConsent: TrackingConsent = .mockRandom(),
        syntheticsEnvironment: Bool = .mockAny()
    ) -> AppStateInfo {
        .init(
            appVersion: appVersion,
            osVersion: osVersion,
            systemBootTime: systemBootTime,
            appLaunchTime: appLaunchTime,
            isDebugging: isDebugging,
            wasTerminated: wasTerminated,
            isActive: isActive,
            vendorId: vendorId,
            processId: processId,
            trackingConsent: trackingConsent,
            syntheticsEnvironment: syntheticsEnvironment
        )
    }
}

public final class WatchdogTerminationReporterMock: WatchdogTerminationReporting {
    public var didSend: XCTestExpectation
    public var sendParams: SendParams?

    public init(didSend: XCTestExpectation) {
        self.didSend = didSend
    }

    public func send(date: Date?, state: DatadogRUM.AppStateInfo, viewEvent: DatadogInternal.RUMViewEvent) {
        sendParams = SendParams(date: date, state: state, viewEvent: viewEvent)
        didSend.fulfill()
    }

    public struct SendParams {
        public let date: Date?
        public let state: AppStateInfo
        public let viewEvent: RUMViewEvent
    }
}

extension WatchdogTerminationReporter: RandomMockable {
    public static func mockRandom() -> Self {
        .init(
            featureScope: FeatureScopeMock(),
            dateProvider: DateProviderMock(),
            uuidGenerator: RUMUUIDGeneratorMock()
        )
    }
}

extension WatchdogTerminationChecker: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationChecker {
        return .init(
            appStateManager: .mockRandom(),
            featureScope: FeatureScopeMock()
        )
    }
}

extension AppStateManager: RandomMockable {
    public static func mockRandom() -> AppStateManager {
        return .init(
            featureScope: FeatureScopeMock(),
            processId: .mockRandom(),
            syntheticsEnvironment: .mockRandom()
        )
    }
}

extension Sysctl: RandomMockable {
    public static func mockRandom() -> DatadogInternal.Sysctl {
        return .init()
    }
}

extension RUMDataStore: RandomMockable {
    public static func mockRandom() -> DatadogRUM.RUMDataStore {
        return .init(featureScope: FeatureScopeMock())
    }
}

extension WatchdogTerminationMonitor: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationMonitor {
        return .init(
            appStateManager: .mockRandom(),
            checker: .mockRandom(),
            storage: NOPDatadogCore().storage,
            feature: FeatureScopeMock(),
            reporter: WatchdogTerminationReporter.mockRandom()
        )
    }
}

extension LaunchReport: RandomMockable {
    public static func mockRandom() -> DatadogInternal.LaunchReport {
        return .init(didCrash: .mockRandom())
    }
}
