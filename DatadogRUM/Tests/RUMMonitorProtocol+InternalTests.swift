/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class RUMMonitorProtocol_InternalTests: XCTestCase {
    func testInternalInterfaceIsAvailableOnMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = Monitor(
            dependencies: .mockAny(),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertIdentical(monitor._internal?.monitor, monitor)
    }

    func testInternalInterfaceIsNotAvailableOnNOPMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = NOPMonitor()

        // Then
        XCTAssertNil(monitor._internal)
    }

    func testInternalCurrentViewCommandsUseExecutionHandoffAndRepresentativeFallback() {
        let monitor = RUMCommandSubscriberMock()
        let interface = DatadogInternalInterface(monitor: monitor)
        let viewID = UUID()
        let context: RUMCoreContext = .mockWith(viewID: viewID.uuidString)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        emitCurrentViewCommands(using: interface)
        XCTAssertEqual(monitor.receivedCommands.map(\.target), Array(repeating: .processRepresentative, count: 4))

        monitor.receivedCommands = []
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: scene.rawValue) {
            emitCurrentViewCommands(using: interface)
        }
        XCTAssertEqual(monitor.receivedCommands.map(\.target), Array(repeating: .scene(scene), count: 4))

        monitor.receivedCommands = []
        RUMContextHandoff.withValue(rumContext: context, sceneIdentifier: "contradictory-scene") {
            emitCurrentViewCommands(using: interface)
        }
        XCTAssertEqual(
            monitor.receivedCommands.map(\.target),
            Array(repeating: .view(RUMUUID(rawValue: viewID)), count: 4)
        )
    }

    func testInternalResourceMetricsRemainOwnerKeyRouted() {
        let monitor = RUMCommandSubscriberMock()
        let interface = DatadogInternalInterface(monitor: monitor)
        let now = Date()

        RUMContextHandoff.withValue(rumContext: .mockAny(), sceneIdentifier: "scene-A") {
            interface.addResourceMetrics(
                at: now,
                resourceKey: "resource",
                fetch: (start: now, end: now),
                redirection: nil,
                dns: nil,
                connect: nil,
                ssl: nil,
                firstByte: nil,
                download: nil
            )
        }

        XCTAssertEqual(monitor.lastReceivedCommand?.target, .processRepresentative)
    }
}

private extension RUMMonitorProtocol_InternalTests {
    func emitCurrentViewCommands(using interface: DatadogInternalInterface) {
        let now = Date()
        interface.addLongTask(at: now, duration: 1)
        interface.updatePerformanceMetric(at: now, metric: .flutterBuildTime, value: 1)
        interface.setInternalViewAttribute(at: now, key: "internal", value: true)
        interface.addAction(at: now, type: .custom, name: "action", heatmapAttributes: nil)
    }
}
