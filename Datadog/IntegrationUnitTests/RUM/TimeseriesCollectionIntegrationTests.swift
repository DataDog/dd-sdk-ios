/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@_spi(Experimental)
@testable import DatadogRUM

/// Verifies memory and CPU timeseries events flow end-to-end through `RUM.enable()` → `RUMFeature` →
/// `RUMSessionScope` → `TimeseriesSessionCollector` → uploaded event, including pause/resume on
/// backgrounding. Uses `.waitRealTime(_:)` since the collector samples on a real timer, independent of
/// `AppRunner`'s fake clock.
class TimeseriesCollectionIntegrationTests: RUMSessionTestsBase {
    /// The collector's real, production default sampling interval (not overridden in these tests).
    private let samplingInterval: TimeInterval = 1
    /// Allowed deviation, in data points, between the expected and observed sample counts.
    private let dataPointsTolerance = 1

    private func enableTimeseries(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return userSession { rumConfig in
            rumConfig.timeseries = .default
            rumSetup?(&rumConfig)
        }
    }

    /// Extracts and decodes all memory timeseries events from the session, in upload order.
    private func memoryEvents(in session: RUMSessionMatcher) throws -> [RUMTimeseriesMemoryEvent] {
        return try session.allEvents
            .filter { (try? $0.eventType()) == "timeseries" }
            .filter { $0.model(isTypeOf: RUMTimeseriesMemoryEvent.self) }
            .map { try $0.model() as RUMTimeseriesMemoryEvent }
    }

    /// Extracts and decodes all CPU timeseries events from the session, in upload order.
    private func cpuEvents(in session: RUMSessionMatcher) throws -> [RUMTimeseriesCpuEvent] {
        return try session.allEvents
            .filter { (try? $0.eventType()) == "timeseries" }
            .filter { $0.model(isTypeOf: RUMTimeseriesCpuEvent.self) }
            .map { try $0.model() as RUMTimeseriesCpuEvent }
    }

    /// Expected number of sampling ticks for a window of `duration`, given `samplingInterval`.
    private func expectedTicks(in duration: TimeInterval) -> Int {
        return Int(duration / samplingInterval)
    }

    func testGivenTimeseriesEnabled_whenAppIsInForeground_itCollectsMemoryAndCpuAndFlushesOnBackground() throws {
        // Given
        let collectionDuration: TimeInterval = 3.5
        let given = enableTimeseries()

        // When — stay in foreground long enough to accumulate several samples, then background (which
        // pauses the collector and flushes its buffered batch)
        let when = given
            .when(.waitRealTime(collectionDuration))
            .and(.appEntersBackground(after: 0))
            .and(.flushDatadogContext())

        // Then
        let session = try when.then().takeSingle()
        let memory = try memoryEvents(in: session)
        let cpu = try cpuEvents(in: session)

        let memoryDataPoints = memory.reduce(0) { $0 + $1.timeseries.data.timestamps.count }
        let cpuDataPoints = cpu.reduce(0) { $0 + $1.timeseries.data.timestamps.count }
        let expected = expectedTicks(in: collectionDuration)

        // Independent per-metric tolerances — CPU and memory sample on independent chains, so their
        // jitter isn't correlated.
        XCTAssertGreaterThan(memoryDataPoints, 0, "Expected at least one memory data point")
        XCTAssertGreaterThan(cpuDataPoints, 0, "Expected at least one CPU data point")
        DDAssertEqual(Double(memoryDataPoints), Double(expected), accuracy: Double(dataPointsTolerance))
        DDAssertEqual(Double(cpuDataPoints), Double(expected), accuracy: Double(dataPointsTolerance))
    }

    func testGivenTimeseriesEnabled_whenAppBackgroundsAndForegroundsTwice_itPausesAndResumesCollection() throws {
        // Given
        let foregroundDuration: TimeInterval = 3.0
        let given = enableTimeseries()

        // When — two foreground windows separated by a background period; sampling should pause while
        // backgrounded and resume once foregrounded again
        let when = given
            .when(.waitRealTime(foregroundDuration))
            .and(.appEntersBackground(after: 0))
            .and(.waitRealTime(foregroundDuration))
            .and(.appBecomesActive(after: 0))
            .and(.waitRealTime(foregroundDuration))
            .and(.appEntersBackground(after: 0))
            .and(.waitRealTime(foregroundDuration))
            .and(.flushDatadogContext())

        // Then — samples accumulate across both foreground windows, not the full elapsed time
        let session = try when.then().takeSingle()
        let memory = try memoryEvents(in: session)
        let cpu = try cpuEvents(in: session)

        let memoryDataPoints = memory.reduce(0) { $0 + $1.timeseries.data.timestamps.count }
        let cpuDataPoints = cpu.reduce(0) { $0 + $1.timeseries.data.timestamps.count }
        let expectedPerWindow = expectedTicks(in: foregroundDuration)

        XCTAssertGreaterThan(memoryDataPoints, 0, "Expected at least one memory data point")
        XCTAssertGreaterThan(cpuDataPoints, 0, "Expected at least one CPU data point")
        DDAssertEqual(Double(memoryDataPoints), Double(2 * expectedPerWindow), accuracy: Double(dataPointsTolerance))
        DDAssertEqual(Double(cpuDataPoints), Double(2 * expectedPerWindow), accuracy: Double(dataPointsTolerance))
        // One flushed batch per background transition.
        XCTAssertEqual(memory.count, 2, "Expected one flushed batch per background transition")
        XCTAssertEqual(cpu.count, 2, "Expected one flushed batch per background transition")
    }
}

#endif
