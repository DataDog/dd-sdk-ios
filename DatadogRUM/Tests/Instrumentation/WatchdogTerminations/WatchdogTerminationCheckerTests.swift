/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationCheckerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var monitor: WatchdogTerminationMonitor!
    private var featureScope: FeatureScopeMock!
    private var sut: WatchdogTerminationChecker!
    private var vendorIdProvider: VendorIdProviderMock!
    private var sysctl: SysctlMock!
    private var deviceInfo: DeviceInfo!
    private var appStateManager: WatchdogTerminationAppStateManager!
    // swiftlint:enable implicitly_unwrapped_optional
    private let app = ApplicationLifeCycle()

    func given(
        isSimulator: Bool,
        isDebugging: Bool,
        appVersion: String,
        osVersion: String,
        systemBootTime: TimeInterval,
        vendorId: String
    ) {
        let deviceInfo: DeviceInfo = .init(
            name: .mockAny(),
            model: .mockAny(),
            osName: .mockAny(),
            osVersion: .mockAny(),
            osBuildNumber: .mockAny(),
            architecture: .mockAny(),
            isSimulator: isSimulator
        )

        featureScope = FeatureScopeMock()
        featureScope.contextMock.version = appVersion

        let dataStore = CodableDataStore(featureScope: featureScope)
        vendorIdProvider = VendorIdProviderMock()
        vendorIdProvider.stubbedVendorId = vendorId
        sysctl = .mockRandom()
        sysctl.stubbedIsDebugging = isDebugging
        sysctl.stubbedOSVersion = osVersion
        sysctl.stubbedSystemBootTime = systemBootTime

        appStateManager = WatchdogTerminationAppStateManager(
            dataStore: dataStore,
            vendorIdProvider: vendorIdProvider,
            featureScope: featureScope,
            sysctl: sysctl
        )

        sut = WatchdogTerminationChecker(
            appStateManager: appStateManager,
            deviceInfo: deviceInfo
        )
    }

    func testIsSimulatorBuild_NoWatchdogTermination() throws {
        given(isSimulator: true, isDebugging: .mockAny(), appVersion: .mockAny(), osVersion: .mockAny(), systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        let launch = LaunchReport.mockRandom()

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testIsDebugging_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: true, appVersion: .mockAny(), osVersion: .mockAny(), systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        let launch = LaunchReport.mockRandom()

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDifferentAppVersions_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: .mockAny(), systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        app.terminateApp()

        featureScope.contextMock.version = "1.0.1"

        app.didFinishLaunching()

        let launch = LaunchReport.mockRandom()

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testApplicationDidCrash_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: .mockAny(), systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        let launch = LaunchReport(didCrash: true)

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testApplicationWasTerminated_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: .mockAny(), systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        app.terminateApp()

        let launch = LaunchReport(didCrash: false)

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDifferentOSVersions_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: "1.0.0", systemBootTime: .mockAny(), vendorId: .mockAny())

        try appStateManager.start()

        sysctl.stubbedOSVersion = "1.0.1"

        let launch = LaunchReport(didCrash: false)

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDifferentBootTimes_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: "1.0.0", systemBootTime: 1.0, vendorId: String.mockAny())

        try appStateManager.start()

        sysctl.stubbedSystemBootTime = 2.0

        let launch = LaunchReport(didCrash: false)

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDifferentVendorId_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: "1.0.0", systemBootTime: 1.0, vendorId: "foo")

        try appStateManager.start()

        app.didFinishLaunching()

        let launch = LaunchReport(didCrash: false)

        appStateManager.vendorIdProvider = VendorIdProviderMock(stubbedVendorId: "bar")

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testApplicationWasInBackground_NoWatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: "1.0.0", systemBootTime: 1.0, vendorId: "foo")

        try appStateManager.start()

        app.goToBackground()

        let launch = LaunchReport(didCrash: false)

        let expectation = self.expectation(description: "isWatchdogTermination is false")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertFalse(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testApplicationWasInForeground_WatchdogTermination() throws {
        given(isSimulator: false, isDebugging: false, appVersion: "1.0.0", osVersion: "1.0.0", systemBootTime: 1.0, vendorId: "foo")

        try appStateManager.start()

        app.goToForeground()

        let launch = LaunchReport(didCrash: false)

        let expectation = self.expectation(description: "isWatchdogTermination is true")

        try sut.isWatchdogTermination(launch: launch) { isWatchdogTermination in
            XCTAssertTrue(isWatchdogTermination)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }
}
