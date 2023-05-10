/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

@testable import Datadog

class RUMInternalProxyTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    /// Creates `RUMMonitor` instance for tests.
    /// The only difference vs. `RUMMonitor.initialize()` is that we disable RUM view updates sampling to get deterministic behaviour.
    private func createTestableRUMMonitor() throws -> DDRUMMonitor {
        let configuration: RUMConfiguration = .mockAny()

        let monitor = RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                core: core,
                configuration: configuration
            ).replacing(viewUpdatesThrottlerFactory: { NoOpRUMViewUpdatesThrottler() }),
            dateProvider: configuration.dateProvider
        )

        let instrumentation = RUMInstrumentation(
            configuration: configuration.instrumentation,
            dateProvider: configuration.dateProvider
        )

        let feature = DatadogRUMFeature(
            monitor: monitor,
            instrumentation: instrumentation,
            requestBuilder: FeatureRequestBuilderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        try core.register(feature: feature)
        return monitor
    }

    func testProxyAddLongTaskSendsLongTasks() throws {
        // Given
        let monitor = try createTestableRUMMonitor()

        let date = Date()
        let duration: TimeInterval = .mockRandom()

        // When
        monitor.startView(viewController: mockView)
        monitor._internal.addLongTask(at: date, duration: duration)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        // Then
        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let longTask = session.viewVisits[0].longTaskEvents.first
        XCTAssertEqual(longTask?.date, (date - duration).timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(longTask?.longTask.duration, duration.toInt64Nanoseconds)
    }

    func testProxyRecordsPerformanceMetricsAreSent() throws {
        // Given
        let date: Date = .mockRandomInThePast()

        let monitor = try createTestableRUMMonitor()

        // When
        monitor.startView(viewController: mockView)
        monitor._internal.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.04)
        monitor._internal.updatePerformanceMetric(at: date, metric: .flutterBuildTime, value: 32.0)
        monitor._internal.updatePerformanceMetric(at: date, metric: .flutterBuildTime, value: 52.0)
        monitor._internal.updatePerformanceMetric(at: date, metric: .flutterRasterTime, value: 42.0)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        // Then
        try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.jsRefreshRate?.max, 50.0)
                XCTAssertEqual(rumModel.view.jsRefreshRate?.min, 25.0)
                XCTAssertEqual(rumModel.view.jsRefreshRate?.average, 40.0)

                XCTAssertEqual(rumModel.view.flutterBuildTime?.max, 52.0)
                XCTAssertEqual(rumModel.view.flutterBuildTime?.min, 32.0)
                XCTAssertEqual(rumModel.view.flutterBuildTime?.average, 42.0)
                XCTAssertEqual(rumModel.view.flutterRasterTime?.average, 42.0)
            }
    }
}
