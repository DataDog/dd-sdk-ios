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

    func testWhenCPUUnderHeavyLoadItMeasuresHigherCPUTicks() throws {
        let cpuReader = VitalCPUReader(notificationCenterProvider: testNotificationCenterProvider)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let duration: TimeInterval = 3

        let before = try XCTUnwrap(cpuReader.readVitalData())
        spinAllCores(cores: cores, for: duration)
        let after = try XCTUnwrap(cpuReader.readVitalData())

        // The counter is host-wide, so other processes can only add user ticks to the ones spun here.
        // The bound is far below what spinning every core yields (> 90% locally), and leaves room
        // for the counter returning a stale value for up to ~1s and for threads not getting a full core.
        let capacity = Double(cores) * 100 * duration // 100 ticks per second per core
        XCTAssertGreaterThan(after - before, 0.25 * capacity)
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

/// Busy-loops compute-only math on `cores` threads until `duration` has elapsed, so that user-mode CPU ticks are consumed.
private func spinAllCores(cores: Int, for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    let group = DispatchGroup()
    for _ in 0..<cores {
        group.enter()
        let thread = Thread {
            var sink = 0.0
            var x: UInt64 = 88_172_645_463_325_252
            while Date() < deadline {
                for _ in 0..<1_000 {
                    x ^= x << 13
                    x ^= x >> 7
                    x ^= x << 17
                    sink += tan(Double(x % 1_000) / 1_000).squareRoot()
                }
            }
            if sink < 0 { print(sink) } // keeps the loop from being optimised away
            group.leave()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }
    group.wait()
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
