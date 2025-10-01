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
        let previous = AppStateInfo(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: true,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: previous, to: .mockRandom()))
    }

    func testDifferentAppVersions_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.1",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationDidCrash_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: true), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasTerminated_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: true,
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentOSVersions_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.1",
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentBootTimes_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 2.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testDifferentVendorId_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "bar",
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testSDKWasStoppedAndStarted_NoWatchdogTermination() throws {
        let pid = UUID()

        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: pid,
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: pid,
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasInBackground_NoWatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: false,
            vendorId: "foo",
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: .mockAny(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }

    func testApplicationWasInForeground_WatchdogTermination() throws {
        let previous = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: true,
            vendorId: "foo",
            processId: UUID(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        let current = AppStateInfo(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: true,
            vendorId: "foo",
            processId: UUID(),
            trackingConsent: .mockRandom(),
            syntheticsEnvironment: false
        )

        XCTAssertTrue(sut.isWatchdogTermination(launch: .init(didCrash: false), deviceInfo: .mockWith(isSimulator: false), from: previous, to: current))
    }
}
