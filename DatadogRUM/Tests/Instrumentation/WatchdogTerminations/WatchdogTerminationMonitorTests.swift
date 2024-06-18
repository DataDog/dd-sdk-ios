/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationMonitorTests: XCTestCase {
    let featureScope = FeatureScopeMock()
    // swiftlint:disable implicitly_unwrapped_optional
    private var sut: WatchdogTerminationMonitor!
    private var core: PassthroughCoreMock!
    // swiftlint:enable implicitly_unwrapped_optional

    func testApplicationWasInForeground_WatchdogTermination() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")

        // app starts
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didSend: didSend
        )
        core.context.applicationStateHistory.append(.init(state: .active, date: .init()))

        // saves the current state
        sut.start(launchReport: nil)

        // watchdog termination happens here which causes app launch
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didSend: didSend
        )
        core.context.applicationStateHistory.append(.init(state: .active, date: .init()))
        sut.start(launchReport: .init(didCrash: false))

        waitForExpectations(timeout: 1)
    }

    // MARK: Helpers

    func given(
        isSimulator: Bool,
        isDebugging: Bool,
        appVersion: String,
        osVersion: String,
        systemBootTime: TimeInterval,
        vendorId: String?,
        processId: UUID,
        didSend: XCTestExpectation
    ) {
        let deviceInfo: DeviceInfo = .init(
            name: .mockAny(),
            model: .mockAny(),
            osName: .mockAny(),
            osVersion: .mockAny(),
            osBuildNumber: .mockAny(),
            architecture: .mockAny(),
            isSimulator: isSimulator,
            vendorId: vendorId,
            isDebugging: false,
            systemBootTime: systemBootTime
        )

        featureScope.contextMock.version = appVersion

        let appStateManager = WatchdogTerminationAppStateManager(
            featureScope: featureScope,
            processId: processId
        )

        let checker = WatchdogTerminationChecker(appStateManager: appStateManager, deviceInfo: deviceInfo)

        let reporter = WatchdogTerminationReporterMock(didSend: didSend)

        sut = WatchdogTerminationMonitor(
            appStateManager: appStateManager,
            checker: checker,
            reporter: reporter,
            telemetry: featureScope.telemetryMock
        )

        core = PassthroughCoreMock(
            context: .mockWith(applicationStateHistory: .mockAppInBackground()),
            messageReceiver: appStateManager
        )
    }
}
