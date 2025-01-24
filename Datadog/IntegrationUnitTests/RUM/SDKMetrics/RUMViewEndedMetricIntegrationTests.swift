/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Experimental)
@testable import DatadogRUM
@testable import DatadogInternal

class RUMViewEndedMetricIntegrationTests: XCTestCase {
    private let dateProvider = DateProviderMock()
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
        core.context = .mockWith(
            launchTime: .mockWith(launchDate: dateProvider.now),
            applicationStateHistory: .mockAppInForeground(since: dateProvider.now)
        )
        rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.telemetrySampleRate = .maxSampleRate
        rumConfig.viewEndedMetricSampleRate = .maxSampleRate
        rumConfig.dateProvider = dateProvider
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    // MARK: - Conditions For Sending The Metric

    func testWhenViewIsStopped() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: "View")
        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].attributes?.viewType, .applicationLaunch)
        XCTAssertEqual(metrics[1].attributes?.viewType, .custom)
    }

    func testWhenAnotherViewIsStarted() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key1", name: "View1")

        // When
        monitor.startView(key: "key2", name: "View2")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].attributes?.viewType, .applicationLaunch)
        XCTAssertEqual(metrics[1].attributes?.viewType, .custom)
    }

    // MARK: - Reporting View Attributes

    func testReportingViewTypeAndDuration() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        dateProvider.now += 1

        // When
        monitor.startView(key: "key1", name: "View1")
        dateProvider.now += 3
        monitor.startView(key: "key2", name: "View2")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].attributes?.viewType, .applicationLaunch)
        XCTAssertNil(metrics[0].attributes?.instrumentationType)
        XCTAssertEqual(metrics[0].attributes?.duration, 1_000_000_000)
        XCTAssertEqual(metrics[1].attributes?.viewType, .custom)
        XCTAssertEqual(metrics[1].attributes?.instrumentationType, .manual)
        XCTAssertEqual(metrics[1].attributes?.duration, 3_000_000_000)
    }

    func testReportingTNSValue() throws {
        rumConfig.networkSettledResourcePredicate = TimeBasedTNSResourcePredicate(threshold: 2)
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When (view with TNS)
        monitor.startView(key: "key", name: "View1")
        dateProvider.now += 1 // less than threshold: 2s
        monitor.startResource(resourceKey: "resource", url: .mockAny())
        dateProvider.now += 4.2
        monitor.stopResource(resourceKey: "resource", response: .mockAny())
        dateProvider.now += 1
        monitor.stopView(key: "key")

        // When (view with no TNS)
        monitor.startView(key: "key", name: "View2")
        dateProvider.now += 1
        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(metrics[1].attributes?.tns?.config, "time_based_custom")
        XCTAssertEqual(try XCTUnwrap(metrics[1].attributes?.tns?.value).nanosecondsToSeconds, 5.2.seconds, accuracy: 0.01)
        XCTAssertEqual(metrics[2].attributes?.tns?.config, "time_based_custom")
        XCTAssertEqual(try XCTUnwrap(metrics[2].attributes?.tns?.noValueReason), "no_resources")
    }

    func testReportingINVValue() throws {
        rumConfig.nextViewActionPredicate = TimeBasedINVActionPredicate(maxTimeToNextView: 5)
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When (view with no INV)
        monitor.startView(key: "key", name: "View1")
        dateProvider.now += 1
        monitor.addAction(type: .tap, name: "Go to View2")
        dateProvider.now += 4.42 // less than maxTimeToNextView: 5
        monitor.stopView(key: "key")

        // When (view with INV)
        monitor.startView(key: "key", name: "View2")
        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(metrics[1].attributes?.inv?.config, "time_based_custom")
        XCTAssertEqual(try XCTUnwrap(metrics[1].attributes?.inv?.noValueReason), "no_action")
        XCTAssertEqual(metrics[2].attributes?.inv?.config, "time_based_custom")
        XCTAssertEqual(try XCTUnwrap(metrics[2].attributes?.inv?.value).nanosecondsToSeconds, 4.42.seconds, accuracy: 0.01)
    }

    func testReportingLoadingTimeValue() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: "View")
        dateProvider.now += 1.52
        monitor.addViewLoadingTime(overwrite: false)
        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewEndedMetricEvents())
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(try XCTUnwrap(metrics[1].attributes?.loadingTime?.value).nanosecondsToSeconds, 1.52.seconds, accuracy: 0.01)
    }
}

// MARK: - Helpers

private extension DatadogCoreProxy {
    func waitAndReturnViewEndedMetricEvents() -> [TelemetryDebugEvent] {
        let events = waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        return events.filter { $0.telemetry.message == "[Mobile Metric] \(ViewEndedMetric.Constants.name)" }
    }
}

private extension TelemetryDebugEvent {
    var attributes: ViewEndedMetric.Attributes? {
        return telemetry.telemetryInfo[ViewEndedMetric.Constants.rveKey] as? ViewEndedMetric.Attributes
    }
}

private extension Int64 {
    var nanosecondsToSeconds: TimeInterval { TimeInterval(fromNanoseconds: self) }
}
