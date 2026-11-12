/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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

    func testSystemProviderReadsHostCPULoadInfo() {
        XCTAssertNoThrow(try SystemHostCPULoadInfoProvider().readHostCPULoadInfo().get())
    }

    func testWhenHostCPULoadInfoCannotBeReadItReturnsNilAndReportsTelemetryError() {
        let telemetry = TelemetryMock()
        let cpuReader = VitalCPUReader(
            notificationCenterProvider: testNotificationCenterProvider,
            telemetry: telemetry,
            hostCPULoadInfoProvider: HostCPULoadInfoProviderMock(mockTicks: [])
        )

        XCTAssertNil(cpuReader.readVitalData())
        XCTAssertEqual(telemetry.messages.firstError()?.message, "CPU Vital cannot be read! Error code: \(KERN_FAILURE)")
    }

    #if !os(watchOS)
    func testWhenInactiveAppStateItIgnoresCPUTicks() throws {
        let cpuReader = VitalCPUReader(
            notificationCenterProvider: testNotificationCenterProvider,
            hostCPULoadInfoProvider: HostCPULoadInfoProviderMock(mockTicks: [100, 110, 210, 310, 330])
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
        let cpuReader = VitalCPUReader(
            notificationCenterProvider: testNotificationCenterProvider,
            hostCPULoadInfoProvider: HostCPULoadInfoProviderMock(
                mockTicks: [
                    tickWhenResigningActive,
                    tickAfterRollover
                ]
            )
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
        let cpuReader = VitalCPUReader(
            notificationCenterProvider: testNotificationCenterProvider,
            hostCPULoadInfoProvider: HostCPULoadInfoProviderMock(
                mockTicks: [
                    tickBeforeRollover,
                    tickAfterRollover
                ]
            )
        )

        let measurementBeforeRollover = try XCTUnwrap(cpuReader.readVitalData())
        let measurementAfterRollover = try XCTUnwrap(cpuReader.readVitalData())

        XCTAssertEqual(measurementAfterRollover - measurementBeforeRollover, 31.0)
    }
}

// Replaces only the OS call reading the host CPU load.
// Rollover normalization and lifecycle accounting stay in VitalCPUReader.
// The user ticks are scripted; the other counters hold values that must never be read.
// Fails once the scripted ticks are exhausted.
private class HostCPULoadInfoProviderMock: HostCPULoadInfoProvider {
    private var mockTicks: [UInt32]

    init(mockTicks: [UInt32]) {
        self.mockTicks = mockTicks
    }

    func readHostCPULoadInfo() -> Result<host_cpu_load_info, HostCPULoadInfoError> {
        guard !mockTicks.isEmpty else {
            return .failure(HostCPULoadInfoError(code: KERN_FAILURE))
        }
        var cpuLoadInfo = host_cpu_load_info()
        cpuLoadInfo.cpu_ticks = (mockTicks.removeFirst(), 1_000, 2_000, 3_000) // user, system, idle, nice
        return .success(cpuLoadInfo)
    }
}
