/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import DatadogCrashReporting
@testable import DatadogRUM

class WatchdogTerminationsMonitoringTests: XCTestCase {
    var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    var rumConfig = RUM.Configuration(applicationID: .mockAny())
    let device: DeviceInfo = .init(
        name: .mockAny(),
        model: .mockAny(),
        osName: .mockAny(),
        osVersion: .mockAny(),
        osBuildNumber: .mockAny(),
        architecture: .mockAny(),
        isSimulator: false,
        vendorId: .mockAny(),
        isDebugging: false,
        systemBootTime: .init()
    )

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        rumConfig.trackWatchdogTerminations = true
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil

        super.tearDown()
    }

    func testGivenRUMAndCrashReportingEnabled_whenWatchdogTerminatesTheApp_thenWatchdogTerminationEventIsReported() throws {
        // given
        core.context = .mockWith(
            device: device,
            trackingConsent: .granted,
            applicationStateHistory: .mockAppInForeground()
        )
        rumConfig.processID = .mockRandom()
        oneOf(
            [ // no matter of RUM or CR initialization order
                {
                    RUM.enable(with: self.rumConfig, in: self.core)
                    CrashReporting.enable(in: self.core)
                },
                {
                    CrashReporting.enable(in: self.core)
                    RUM.enable(with: self.rumConfig, in: self.core)
                },
            ]
        )

        try waitForWatchdogTerminationCheck(core: core)
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "foo")
        let views = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMViewEvent.self)
        let errorsBeforeCrash = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        XCTAssertEqual(errorsBeforeCrash.count, 0)

        let erroringView = try XCTUnwrap(views.last)
        XCTAssertEqual(erroringView.view.name, "foo")

        core.context = .mockWith(
            device: device,
            trackingConsent: .pending,
            applicationStateHistory: .mockAppInForeground()
        )

        // re-enable RUM to trigger the watchdog termination event
        // update the process ID to make sure check treats it as a new app launch
        rumConfig.processID = .mockRandom()
        oneOf(
            [ // no matter of RUM or CR initialization order
                {
                    RUM.enable(with: self.rumConfig, in: self.core)
                    CrashReporting.enable(in: self.core)
                },
                {
                    CrashReporting.enable(in: self.core)
                    RUM.enable(with: self.rumConfig, in: self.core)
                },
            ]
        )

        try waitForWatchdogTerminationCheck(core: core)

        let errors = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self)
        let watchdogCrash = try XCTUnwrap(errors.first)
        XCTAssertEqual(watchdogCrash.error.stack, WatchdogTerminationReporter.Constants.stackNotAvailableErrorMessage)
        XCTAssertEqual(watchdogCrash.view.name, "foo")

        XCTAssertEqual(watchdogCrash.error.message, WatchdogTerminationReporter.Constants.errorMessage)
        XCTAssertEqual(watchdogCrash.error.type, WatchdogTerminationReporter.Constants.errorType)
        XCTAssertEqual(watchdogCrash.error.source, .source)
        XCTAssertEqual(watchdogCrash.error.category, .watchdogTermination)
    }

    /// Watchdog Termination check is done in the background, we need to wait for it to finish before we can proceed with the test
    /// - Parameter core: `DatadogCoreProxy` instance
    func waitForWatchdogTerminationCheck(core: DatadogCoreProxy) throws {
        let watchdogTermination = try XCTUnwrap(core.get(feature: RUMFeature.self)?.instrumentation.watchdogTermination)
        while watchdogTermination.currentState != .started {
            Thread.sleep(forTimeInterval: .fromMilliseconds(100))
        }
    }
}
