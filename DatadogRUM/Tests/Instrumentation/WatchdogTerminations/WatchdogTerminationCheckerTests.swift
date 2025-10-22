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
    var sut: WatchdogTerminationChecker = .init(appStateManager: .mockRandom(), featureScope: FeatureScopeMock())

    func testNoPreviousState_NoWatchdogTermination() throws {
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: nil, to: .mockRandom()))
    }

    func testSyntheticsEnvironment_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            appLaunchTime: .mockAny(),
            isDebugging: true,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: true
        )
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: previous, to: .mockRandom()))
    }

    func testIsSimulatorBuild_NoWatchdogTermination() throws {
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: .mockRandom(), to: .mockRandom()))
    }

    func testIsDebugging_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            isDebugging: true,
            syntheticsEnvironment: false
        )
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: previous, to: .mockRandom()))
    }

    func testDifferentAppVersions_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            isDebugging: false,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.1",
            isDebugging: false,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationDidCrash_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            isDebugging: false,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            isDebugging: false,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: true), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasTerminated_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            isDebugging: false,
            wasTerminated: true,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            isDebugging: false,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentOSVersions_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            isDebugging: false,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.1",
            isDebugging: false,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentBootTimes_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 2.0,
            isDebugging: false,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentVendorId_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            vendorId: "foo",
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            vendorId: "bar",
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testSDKWasStoppedAndStarted_NoWatchdogTermination() throws {
        let pid = UUID()

        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            vendorId: "foo",
            processId: pid,
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            vendorId: "foo",
            processId: pid,
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasInBackground_NoWatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            isActive: false,
            vendorId: "foo",
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            vendorId: "foo",
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasInForeground_WatchdogTermination() throws {
        let previous: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            isActive: true,
            vendorId: "foo",
            processId: UUID(),
            syntheticsEnvironment: false
        )

        let current: AppStateInfo = .mockWith(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            isActive: true,
            vendorId: "foo",
            processId: UUID(),
            syntheticsEnvironment: false
        )

        XCTAssertTrue(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }
}
