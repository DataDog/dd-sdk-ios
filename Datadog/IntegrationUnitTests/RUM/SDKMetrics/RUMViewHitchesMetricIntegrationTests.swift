/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM
@testable import DatadogInternal

final class RUMViewHitchesMetricIntegrationTests: XCTestCase {
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
        rumConfig.viewEndedSampleRate = .maxSampleRate
        rumConfig.dateProvider = dateProvider
        rumConfig.featureFlags = [.viewHitches: true]
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    func testViewHitchesDefaultConfigForTelemetry() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: "View1")
        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewHitchesMetricEvents())
        let attributes = metrics.compactMap { $0.attributes }
        XCTAssertEqual(attributes.count, 2) // Telemetry Attributes for ApplicationLaunch and View1

        try attributes.forEach {
            let config = try XCTUnwrap($0.slowFrames.config)
            XCTAssertGreaterThan(config.maxCount, 0)
            XCTAssertGreaterThan(config.maxDuration, 0)
            XCTAssertGreaterThan(config.viewMinDuration, 0)
        }
    }

    func testViewDurationCollectedForTelemetry() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        dateProvider.now += 1

        // When
        monitor.startView(key: "key1", name: "View1")
        dateProvider.now += 3
        monitor.startView(key: "key2", name: "View2")
        dateProvider.now += 2
        monitor.stopView(key: "key2")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewHitchesMetricEvents())
        let attributes = metrics.compactMap { $0.attributes }

        // ApplicationLaunch
        XCTAssertEqual(attributes[0].viewDuration, 1_000_000_000)
        // View1
        XCTAssertEqual(attributes[1].viewDuration, 3_000_000_000)
        // View2
        XCTAssertEqual(attributes[2].viewDuration, 2_000_000_000)
    }

    func testViewHitchesCollectedForTelemetry() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: "View1")

        let completion = expectation(description: "Wait for some slow frames")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // sleep main thread to have some slow frames
            Thread.sleep(forTimeInterval: 0.1)

            // schedule completion to the next runloop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion.fulfill() }
        }

        wait(for: [completion], timeout: 2)

        monitor.stopView(key: "key")

        // Then
        let metrics = try XCTUnwrap(core.waitAndReturnViewHitchesMetricEvents())
        let attributes = metrics.compactMap { $0.attributes }
        XCTAssertEqual(attributes.count, 2) // Telemetry Attributes for ApplicationLaunch and View1

        // ApplicationLaunch has 0 Slow Frames
        XCTAssertEqual(attributes[0].slowFrames.count, 0)

        // View1 has Slow Frames
        XCTAssertGreaterThan(attributes[1].slowFrames.count, 0)
    }
}

// MARK: - Helpers

private extension DatadogCoreProxy {
    func waitAndReturnViewHitchesMetricEvents() -> [TelemetryDebugEvent] {
        let events = waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        return events.filter { $0.telemetry.message == "[Mobile Metric] \(ViewHitchesMetric.Constants.name)" }
    }
}

private extension TelemetryDebugEvent {
    var attributes: ViewHitchesMetric.Attributes? {
        telemetry.telemetryInfo[ViewHitchesMetric.Constants.uiSlownessKey] as? ViewHitchesMetric.Attributes
    }
}
