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
    var sut: WatchdogTerminationMonitor!
    var reporter: WatchdogTerminationReporterMock!
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
            didCrash: false,
            didSend: didSend
        )

        // RUM view update before start, this must be ignored
        let viewEvent1: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent1)

        // monitor reveives the launch report
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        // RUM view update after start
        let viewEvent2: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent2)

        // watchdog termination happens here which causes app launch
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didCrash: false,
            didSend: didSend
        )

        // RUM view update before start, this must be ignored
        let viewEvent3: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent3)

        // monitor reveives the launch report
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 1)
        XCTAssertEqual(reporter.sendParams?.viewEvent.view.id, viewEvent2.view.id)
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
        didCrash: Bool,
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
        featureScope.contextMock.device = deviceInfo
        featureScope.contextMock.baggages[LaunchReport.baggageKey] = .init(LaunchReport(didCrash: didCrash))

        let appStateManager = WatchdogTerminationAppStateManager(
            featureScope: featureScope,
            processId: processId,
            syntheticsEnvironment: false
        )

        let checker = WatchdogTerminationChecker(appStateManager: appStateManager, featureScope: featureScope)

        reporter = WatchdogTerminationReporterMock(didSend: didSend)

        sut = WatchdogTerminationMonitor(
            appStateManager: appStateManager,
            checker: checker,
            stroage: NOPDatadogCore().storage,
            feature: featureScope,
            reporter: reporter
        )
    }
}
