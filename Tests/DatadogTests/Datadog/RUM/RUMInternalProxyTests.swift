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
        RUM.enable(with: .mockAny(), in: core)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testProxyAddLongTaskSendsLongTasks() throws {
        // Given
        let monitor = RUMMonitor.shared(in: core)

        let date = Date()
        let duration: TimeInterval = .mockRandom()

        // When
        monitor.startView(viewController: mockView)
        monitor._internal?.addLongTask(at: date, duration: duration)

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
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(viewController: mockView)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.02)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .jsFrameTimeSeconds, value: 0.04)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .flutterBuildTime, value: 32.0)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .flutterBuildTime, value: 52.0)
        monitor._internal?.updatePerformanceMetric(at: date, metric: .flutterRasterTime, value: 42.0)
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

    func testProxyRecordsCustomResourceMetrics() throws {
        // Given
        let date: Date = .mockDecember15th2019At10AMUTC()
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(viewController: mockView)
        monitor.startResource(resourceKey: "/resource/1", request: .mockWith(httpMethod: "POST"))

        let fetch = (start: date, end: date.addingTimeInterval(12))
        let redirection = (start: date.addingTimeInterval(1), end: date.addingTimeInterval(2))
        let dns = (start: date.addingTimeInterval(3), end: date.addingTimeInterval(4))
        let connect = (start: date.addingTimeInterval(5), end: date.addingTimeInterval(6))
        let ssl = (start: date.addingTimeInterval(7), end: date.addingTimeInterval(8))
        let firstByte = (start: date.addingTimeInterval(9), end: date.addingTimeInterval(10))
        let download = (start: date.addingTimeInterval(11), end: date.addingTimeInterval(12))

        monitor._internal?.addResourceMetrics(
            at: date.addingTimeInterval(-1),
            resourceKey: "/resource/1",
            fetch: fetch,
            redirection: redirection,
            dns: dns,
            connect: connect,
            ssl: ssl,
            firstByte: firstByte,
            download: download,
            responseSize: 42
        )

        monitor.stopResource(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        // Then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.type, .native, "POST Resources should always have the `.native` kind")
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)

        XCTAssertEqual(resourceEvent.resource.duration, 12_000_000_000)

        XCTAssertEqual(resourceEvent.resource.redirect!.start, 1_000_000_000)
        XCTAssertEqual(resourceEvent.resource.redirect!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.dns!.start, 3_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.connect!.start, 5_000_000_000)
        XCTAssertEqual(resourceEvent.resource.connect!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.ssl!.start, 7_000_000_000)
        XCTAssertEqual(resourceEvent.resource.ssl!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.firstByte!.start, 9_000_000_000)
        XCTAssertEqual(resourceEvent.resource.firstByte!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.download!.start, 11_000_000_000)
        XCTAssertEqual(resourceEvent.resource.download!.duration, 1_000_000_000)
    }
}
