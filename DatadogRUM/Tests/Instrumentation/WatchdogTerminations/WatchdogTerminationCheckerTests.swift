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
    var sut: WatchdogTerminationChecker!
    // swiftlint:enable implicitly_unwrapped_optional

    func testNoPreviousState_NoWatchdogTermination() throws {
        given(isSimulator: .mockRandom())

        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), from: nil, to: .mockRandom()))
    }

    func testIsSimulatorBuild_NoWatchdogTermination() throws {
        given(isSimulator: true)

        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), from: .mockRandom(), to: .mockRandom()))
    }

    func testIsDebugging_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: true,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )
        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), from: previous, to: .mockRandom()))
    }

    func testDifferentAppVersions_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.1",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .mockRandom(), from: previous, to: current))
    }

    func testApplicationDidCrash_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: .mockAny(),
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: true), from: previous, to: current))
    }

    func testApplicationWasTerminated_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: true,
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: .mockAny(),
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testDifferentOSVersions_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.1",
            systemBootTime: .mockAny(),
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testDifferentBootTimes_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 2.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: .mockAny(),
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testDifferentVendorId_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "bar",
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testSDKWasStoppedAndStarted_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let pid = UUID()

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: pid
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: pid
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testApplicationWasInBackground_NoWatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: false,
            vendorId: "foo",
            processId: .mockAny()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: .mockAny(),
            vendorId: "foo",
            processId: .mockAny()
        )

        XCTAssertFalse(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    func testApplicationWasInForeground_WatchdogTermination() throws {
        given(isSimulator: false)

        let previous = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: true,
            vendorId: "foo",
            processId: UUID()
        )

        let current = WatchdogTerminationAppState(
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            isDebugging: false,
            wasTerminated: .mockAny(),
            isActive: true,
            vendorId: "foo",
            processId: UUID()
        )

        XCTAssertTrue(sut.isWatchdogTermination(launch: .init(didCrash: false), from: previous, to: current))
    }

    // MARK: Helpers

    func given(isSimulator: Bool) {
        let deviceInfo: DeviceInfo = .init(
            name: .mockAny(),
            model: .mockAny(),
            osName: .mockAny(),
            osVersion: .mockAny(),
            osBuildNumber: .mockAny(),
            architecture: .mockAny(),
            isSimulator: isSimulator,
            vendorId: .mockAny(),
            isDebugging: .mockAny(),
            systemBootTime: .mockAny()
        )

        sut = WatchdogTerminationChecker(
            appStateManager: .mockRandom(),
            deviceInfo: deviceInfo
        )
    }
}
