/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

extension WatchdogTerminationAppState: RandomMockable, AnyMockable {
    public static func mockAny() -> DatadogRUM.WatchdogTerminationAppState {
        return .init(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: .mockAny(),
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )
    }

    public static func mockRandom() -> WatchdogTerminationAppState {
        return .init(
            appVersion: .mockRandom(),
            osVersion: .mockRandom(),
            systemBootTime: .mockRandom(),
            isDebugging: .mockRandom(),
            wasTerminated: .mockRandom(),
            isActive: .mockRandom(),
            vendorId: .mockRandom(),
            processId: .mockAny()
        )
    }
}

class WatchdogTerminationReporterMock: WatchdogTerminationReporting {
    var didSend: XCTestExpectation

    init(didSend: XCTestExpectation) {
        self.didSend = didSend
    }

    func send() {
        didSend.fulfill()
    }
}

extension WatchdogTerminationReporter: RandomMockable {
    public static func mockRandom() -> Self {
        return .init()
    }
}

extension WatchdogTerminationChecker: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationChecker {
        return .init(
            appStateManager: .mockRandom(),
            deviceInfo: .mockRandom()
        )
    }
}

extension WatchdogTerminationAppStateManager: RandomMockable {
    public static func mockRandom() -> WatchdogTerminationAppStateManager {
        return .init(
            featureScope: FeatureScopeMock(),
            processId: .mockRandom()
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
            reporter: WatchdogTerminationReporter.mockRandom(),
            telemetry: NOPTelemetry()
        )
    }
}

extension LaunchReport: RandomMockable {
    public static func mockRandom() -> DatadogInternal.LaunchReport {
        return .init(didCrash: .mockRandom())
    }
}
