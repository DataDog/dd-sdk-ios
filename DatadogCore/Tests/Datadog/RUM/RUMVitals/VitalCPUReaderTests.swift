/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

class VitalCPUReaderTest: XCTestCase {
    let testNotificationCenterProvider = NotificationCenterProvider.makeTestProvider()

    func testReadCPUTicks() throws {
        // Runs the concrete implementation: the OS call must succeed and the counter must not go backwards.
        // The values depend on the host load, so they are not asserted.
        let cpuReader = VitalCPUReader(notificationCenterProvider: testNotificationCenterProvider)
        let firstMeasurement = try XCTUnwrap(cpuReader.readVitalData())
        let secondMeasurement = try XCTUnwrap(cpuReader.readVitalData())

        XCTAssertGreaterThanOrEqual(secondMeasurement, firstMeasurement)
    }

    func testItReadsUserTicksFromHostCPULoadInfo() {
        var cpuLoadInfo = host_cpu_load_info()
        cpuLoadInfo.cpu_ticks = (1, 2, 3, 4) // user, system, idle, nice

        XCTAssertEqual(VitalCPUReader.userTicks(from: cpuLoadInfo), 1)
    }

    #if !os(watchOS)
    func testWhenInactiveAppStateItIgnoresCPUTicks() throws {
        let cpuReader = VitalCPUReaderMock(
            notificationCenterProvider: testNotificationCenterProvider,
            mockTicks: [100, 110, 210, 310, 330]
        )
        let baseline = try XCTUnwrap(cpuReader.readVitalData())
        #if os(macOS)
        testNotificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.willSleep, object: nil)
        #else
        testNotificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        #endif
        let measurementWhenInactive = try XCTUnwrap(cpuReader.readVitalData())
        #if os(macOS)
        testNotificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        #else
        testNotificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        #endif
        let measurementWhenActive = try XCTUnwrap(cpuReader.readVitalData())

        let diffWhenInactive = measurementWhenInactive - baseline
        let diffWhenActive = measurementWhenActive - measurementWhenInactive

        XCTAssertEqual(diffWhenInactive, 10)
        XCTAssertEqual(diffWhenActive, 20)
    }
    #endif

    func testWhenCPUCounterRollsOverWhileAppIsInactiveItDoesNotCrash() throws {
        let tickWhenResigningActive = UInt32.max - 10
        let tickAfterRollover: UInt32 = 20
        let cpuReader = VitalCPUReaderMock(
            notificationCenterProvider: testNotificationCenterProvider,
            mockTicks: [
                tickWhenResigningActive,
                tickAfterRollover
            ]
        )

        #if os(macOS)
        testNotificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.willSleep, object: nil)
        #else
        testNotificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        #endif

        let measurementWhenInactive = try XCTUnwrap(cpuReader.readVitalData())
        XCTAssertEqual(measurementWhenInactive, Double(tickWhenResigningActive))
    }

    func testWhenCPUCounterRollsOverWhileAppIsActiveItAccumulatesElapsedTicks() throws {
        let tickBeforeRollover = UInt32.max - 10
        let tickAfterRollover: UInt32 = 20
        let cpuReader = VitalCPUReaderMock(
            notificationCenterProvider: testNotificationCenterProvider,
            mockTicks: [
                tickBeforeRollover,
                tickAfterRollover
            ]
        )

        let measurementBeforeRollover = try XCTUnwrap(cpuReader.readVitalData())
        let measurementAfterRollover = try XCTUnwrap(cpuReader.readVitalData())

        XCTAssertEqual(measurementAfterRollover - measurementBeforeRollover, 31.0)
    }
}

// Overrides only the OS counter read.
// Rollover normalization and lifecycle accounting stay in VitalCPUReader.
private class VitalCPUReaderMock: VitalCPUReader {
    private var mockTicks: [UInt32]

    init(notificationCenterProvider: NotificationCenterProvider, mockTicks: [UInt32]) {
        self.mockTicks = mockTicks
        super.init(notificationCenterProvider: notificationCenterProvider)
    }

    override func readRawUtilizedTicks() -> UInt32? {
        mockTicks.isEmpty ? nil : mockTicks.removeFirst()
    }
}
