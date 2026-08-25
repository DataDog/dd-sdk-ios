/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import TestUtilities
import DatadogInternal
@_spi(Experimental)
@testable import DatadogRUM

class TimeseriesSessionCollectorTests: XCTestCase {
    private let featureScope = FeatureScopeMock(context: .mockWith(additionalContext: [RUMCoreContext.mockAny()]))
    private let memoryReader = SamplingBasedVitalReaderMock()

    // MARK: - Memory events

    func testWhenBatchSizeIsReached_itWritesMemoryEvent() {
        // Given
        memoryReader.vitalData = 1_024_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-abc", applicationID: "app-123", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-abc")

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected at least one memory batch to be written")

        let event = events[0]
        XCTAssertEqual(event.session.id, "session-abc")
        XCTAssertEqual(event.application.id, "app-123")
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.timeseries.name, "memory")
        XCTAssertEqual(event.timeseries.schema, "object-v2")
        XCTAssertEqual(event.timeseries.data.timestamps.count, 2)
        XCTAssertEqual(event.timeseries.data.values.memoryFootprint.count, event.timeseries.data.timestamps.count, "Number of memoryFootprint data points must match timestamps")
        XCTAssertEqual(event.timeseries.data.values.memoryPercent.count, event.timeseries.data.timestamps.count, "Number of memoryPercent data points must match timestamps")
        XCTAssertEqual(event.timeseries.data.values.memoryFootprint[0], 1_000)
        XCTAssertEqual(event.timeseries.data.values.memoryPercent[0], 0.0256, accuracy: 0.0001)
    }

    func testWhenBatchSizeIsReached_itWritesCpuEvent() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { 42.5 }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "cpu batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-abc", applicationID: "app-123", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-abc")

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected at least one CPU batch to be written")

        let event = events[0]
        XCTAssertEqual(event.session.id, "session-abc")
        XCTAssertEqual(event.application.id, "app-123")
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.timeseries.name, "cpu")
        XCTAssertEqual(event.timeseries.schema, "object-v2")
        XCTAssertEqual(event.timeseries.data.timestamps.count, 2)
        XCTAssertEqual(event.timeseries.data.values.cpuUsage.count, event.timeseries.data.timestamps.count, "Number of cpuUsage data points must match timestamps")
        XCTAssertEqual(event.timeseries.data.values.cpuUsage[0], 42.5)
    }

    func testWhenBothReadersProvideData_itWritesBothMemoryAndCpuEvents() {
        // Given
        memoryReader.vitalData = 2_048_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { 75.0 },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "both batches written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-both", applicationID: "app-both", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-both")

        // Then
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected memory events")
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty, "Expected CPU events")
        let memoryEvent = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)[0]
        let cpuEvent = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)[0]
        XCTAssertEqual(memoryEvent.timeseries.data.values.memoryFootprint.count, memoryEvent.timeseries.data.timestamps.count, "Number of memoryFootprint data points must match timestamps")
        XCTAssertEqual(memoryEvent.timeseries.data.values.memoryPercent.count, memoryEvent.timeseries.data.timestamps.count, "Number of memoryPercent data points must match timestamps")
        XCTAssertEqual(cpuEvent.timeseries.data.values.cpuUsage.count, cpuEvent.timeseries.data.timestamps.count, "Number of cpuUsage data points must match timestamps")
        XCTAssertEqual(memoryEvent.timeseries.data.values.memoryFootprint[0], 2_000)
        XCTAssertEqual(cpuEvent.timeseries.data.values.cpuUsage[0], 75.0)
    }

    // MARK: - collectTypes

    func testWhenCollectTypesIsDefault_itCollectsBothMemoryAndCpu() {
        // Given
        memoryReader.vitalData = 1_024_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { 42.5 },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "both batches written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-collect-all", applicationID: "app-collect-all", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-collect-all")

        // Then
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected memory events when collectTypes defaults to all available types")
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty, "Expected CPU events when collectTypes defaults to all available types")
    }

    func testWhenCollectTypesIsMemory_itCollectsOnlyMemory() {
        // Given
        memoryReader.vitalData = 1_024_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            collectTypes: [.memory],
            samplingInterval: 0.05,
            cpuUsageProvider: { 42.5 },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-collect-memory", applicationID: "app-collect-memory", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-collect-memory")

        // Then
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected memory events when collectTypes is [.memory]")
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty, "Expected no CPU events when collectTypes is [.memory]")
    }

    func testWhenCollectTypesIsCpu_itCollectsOnlyCpu() {
        // Given
        memoryReader.vitalData = 1_024_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            collectTypes: [.cpu],
            samplingInterval: 0.05,
            cpuUsageProvider: { 42.5 },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "cpu batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-collect-cpu", applicationID: "app-collect-cpu", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-collect-cpu")

        // Then
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected no memory events when collectTypes is [.cpu]")
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty, "Expected CPU events when collectTypes is [.cpu]")
    }

    func testWhenCollectTypesIsBothTypes_itCollectsBothMemoryAndCpu() {
        // Given
        memoryReader.vitalData = 1_024_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            collectTypes: [.memory, .cpu],
            samplingInterval: 0.05,
            cpuUsageProvider: { 42.5 },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "both batches written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-collect-both", applicationID: "app-collect-both", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-collect-both")

        // Then
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected memory events when collectTypes is [.memory, .cpu]")
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty, "Expected CPU events when collectTypes is [.memory, .cpu]")
    }

    func testWhenServerTimeOffsetIsNonZero_itAdjustsEventDate() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(serverTimeOffset: 5.0, additionalContext: [RUMCoreContext.mockAny()]))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-offset", applicationID: "app-offset", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-offset")

        // Then — date and data point timestamps are server-adjusted
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        let event = events[0]
        // timeseries.start is offset-adjusted ns; date is offset-adjusted ms
        let expectedDateMs = event.timeseries.start / 1_000_000
        XCTAssertEqual(event.date, expectedDateMs, accuracy: 100)
        XCTAssertEqual(event.timeseries.data.timestamps[0], event.timeseries.start)
    }

    func testWhenContextSourceIsReactNative_itUsesContextSource() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(source: "react-native", additionalContext: [RUMCoreContext.mockAny()]))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-rn", applicationID: "app-rn", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-rn")

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].source, .reactNative)
    }

    func testWhenActiveViewExists_itStillWritesEventWithoutView() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: []))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(activeView: (id: "view-abc", path: "/view/abc", name: "ViewController"))
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-view", applicationID: "app-view", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-view")

        // Then — `view` is never populated on timeseries events, even when a view is active
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertNil(events[0].view)
    }

    func testWhenSessionReplayHasReplay_itAttachesHasReplayToEvent() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(hasReplay: true)
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-has-replay", applicationID: "app-has-replay", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-has-replay")

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].session.hasReplay, true)
    }

    func testWhenSessionReplayContextNeverObserved_hasReplayStaysNilOnEvent() {
        // Given — no `hasReplay` value is ever reported by the active context reader (Session Replay not enabled)
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(hasReplay: nil)
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-no-replay", applicationID: "app-no-replay", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-no-replay")

        // Then — `hasReplay` stays `nil`, not `false`, so the field is omitted rather than misreported
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertNil(events[0].session.hasReplay)
    }

    func testWhenReplayStopsBeforeFlush_hasReplayStaysTrueForTheBatch() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only `stop()` triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(hasReplay: true)
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-replay-stops", applicationID: "app-1", sessionType: .user)

        // When — replay was active for some of the batch window, then stops before the flush
        let replayActiveExpectation = self.expectation(description: "samples collected while replay is active")
        replayActiveExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            contextReader.hasReplay = false
            replayActiveExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        let moreSamplesExpectation = self.expectation(description: "more samples collected after replay stopped")
        moreSamplesExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { moreSamplesExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-replay-stops")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the whole batch still reports `hasReplay: true`, since replay was active for part of it
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].session.hasReplay, true)
    }

    func testItPopulatesSessionSampleRateFromConstructorInjectedValue() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [RUMCoreContext.mockAny()]))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            sessionSampleRate: 42
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-sample-rate", applicationID: "app-sample-rate", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-sample-rate")

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].dd.configuration?.sessionSampleRate, 42)
    }

    func testWhenNoActiveView_itWritesEventWithoutView() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: []))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )

        // When — no `activeContextReader` set, so there is no active view to report
        let expectation = self.expectation(description: "samples collected")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-no-view", applicationID: "app-no-view", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-no-view")

        // Then — no view context means the batch is still written, just with `view: nil`, not dropped
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected the batch collected without an active view to be flushed with view: nil, not dropped")
        XCTAssertNil(events[0].view)
    }

    func testWhenStartIsCalledWithoutStop_itFlushesPartialBufferBeforeNewSession() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // Accumulate some samples in session-1
        let firstExpectation = self.expectation(description: "first session samples")
        firstExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { firstExpectation.fulfill() }
        collector.start(sessionID: "session-1", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        // Start session-2 without calling stop() first
        let secondExpectation = self.expectation(description: "session-2 started")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { secondExpectation.fulfill() }
        collector.start(sessionID: "session-2", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        // Then — session-1's partial buffer was flushed and labelled with session-1
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected session-1 partial buffer to be flushed on re-start")
        XCTAssertEqual(events[0].session.id, "session-1")
        collector.stop(sessionID: "session-2")
    }

    // MARK: - Flush on stop

    func testWhenStopIsCalled_itFlushesPartialMemoryBuffer() {
        // Given
        memoryReader.vitalData = 2_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // large batch — won't auto-flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When — let a few samples accumulate then stop
        let expectation = self.expectation(description: "samples collected")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }

        collector.start(sessionID: "session-xyz", applicationID: "app-456", sessionType: .synthetics)
        waitForExpectations(timeout: 2)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-xyz")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected partial buffer to be flushed on stop")
        XCTAssertEqual(events[0].session.id, "session-xyz")
        XCTAssertEqual(events[0].application.id, "app-456")
        XCTAssertEqual(events[0].session.type, .synthetics)
        XCTAssertEqual(events[0].timeseries.data.values.memoryFootprint.count, events[0].timeseries.data.timestamps.count, "Number of memoryFootprint data points must match timestamps")
        XCTAssertEqual(events[0].timeseries.data.values.memoryPercent.count, events[0].timeseries.data.timestamps.count, "Number of memoryPercent data points must match timestamps")
    }

    func testWhenStopIsCalled_itFlushesPartialCpuBuffer() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100,
            samplingInterval: 0.05,
            cpuUsageProvider: { 10.0 }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        let expectation = self.expectation(description: "samples collected")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }

        collector.start(sessionID: "session-xyz", applicationID: "app-456", sessionType: .ciTest)
        waitForExpectations(timeout: 2)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-xyz")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected partial CPU buffer to be flushed on stop")
        XCTAssertEqual(events[0].session.type, .ciTest)
        XCTAssertEqual(events[0].timeseries.data.values.cpuUsage.count, events[0].timeseries.data.timestamps.count, "Number of cpuUsage data points must match timestamps")
    }

    // MARK: - No-data readers

    func testWhenReadersReturnNil_itWritesNoEvents() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )

        let expectation = self.expectation(description: "sampling time elapsed")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }

        collector.start(sessionID: "session-abc", applicationID: "app-123", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-abc")

        // Then
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty)
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self).isEmpty)
    }

    // MARK: - Session restart

    func testWhenStartIsCalledAgain_itUsesNewSessionMetadata() throws {
        // Given
        memoryReader.vitalData = 512_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // First session
        let firstExpectation = self.expectation(description: "first session samples")
        firstExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { firstExpectation.fulfill() }
        collector.start(sessionID: "session-1", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        // Second session — start() resets buffers and updates metadata
        let secondExpectation = self.expectation(description: "second session samples")
        secondExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { secondExpectation.fulfill() }
        collector.start(sessionID: "session-2", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        // Flush second session
        let stopExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-2")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { stopExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the flushed event should carry session-2 metadata
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        let lastEvent = try XCTUnwrap(events.last)
        XCTAssertEqual(lastEvent.session.id, "session-2")
    }

    // MARK: - Pause / resume

    func testWhenPaused_itStopsCollectingSamples() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        let samplingExpectation = self.expectation(description: "initial samples collected")
        samplingExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { samplingExpectation.fulfill() }

        collector.start(sessionID: "session-pause", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        let countBeforePause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertGreaterThan(countBeforePause, 0, "Should have collected events before pause")

        // When — pause and wait for more potential samples
        let pauseExpectation = self.expectation(description: "pause settled")
        collector.pause(sessionID: "session-pause")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { pauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — pause() flushes the partial buffer; no further events written
        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertGreaterThanOrEqual(countAfterPause, countBeforePause, "pause() must not drop buffered data")

        let countAfterSettle = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertEqual(countAfterPause, countAfterSettle, "No further events should be written while paused")
        collector.stop(sessionID: "session-pause")
    }

    func testWhenResumedAfterPause_itContinuesSampling() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        collector.start(sessionID: "session-resume", applicationID: "app-1", sessionType: .user)

        let pauseExpectation = self.expectation(description: "pause settled")
        collector.pause(sessionID: "session-resume")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { pauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count

        // When — resume and let samples accumulate
        let resumeExpectation = self.expectation(description: "resumed samples collected")
        resumeExpectation.assertForOverFulfill = false
        collector.resume(sessionID: "session-resume")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resumeExpectation.fulfill() }
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-resume")

        // Then — new events were written after resume
        let countAfterResume = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertGreaterThan(countAfterResume, countAfterPause, "Expected new events after resume")
    }

    func testWhenBackgrounded_pauseAlwaysStopsSampling() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        let startExpectation = self.expectation(description: "initial samples")
        startExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startExpectation.fulfill() }

        collector.start(sessionID: "session-bg", applicationID: "app-1", sessionType: .user)
        waitForExpectations(timeout: 2)

        let countBeforePause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertGreaterThan(countBeforePause, 0)

        // When — pause on backgrounding
        let afterPauseExpectation = self.expectation(description: "sampling stopped after pause")
        afterPauseExpectation.assertForOverFulfill = false
        collector.pause(sessionID: "session-bg")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { afterPauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — no new events accumulate while paused
        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertEqual(countAfterPause, countBeforePause, "Sampling should stop while backgrounded, regardless of trackBackgroundEvents")
        collector.stop(sessionID: "session-bg")
    }

    func testWhenResumedAfterPause_reanchorsToAvoidLagOrPrecedeAlreadyFlushedSamples() {
        // Given — the media clock doesn't advance during real device sleep (unlike the wall clock), so a
        // pause spanning device sleep leaves a growing gap between the two if the anchor isn't refreshed
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only `pause()`/`stop()` triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-clock-jumps", applicationID: "app-1", sessionType: .user)

        let pauseExpectation = self.expectation(description: "pause settled")
        collector.pause(sessionID: "session-clock-jumps")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { pauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // When — simulate a long device sleep: the wall clock jumps forward by an hour, but the monotonic
        // media clock (paused during real sleep) does not advance — then the collector resumes and samples
        clock.date = clock.date.addingTimeInterval(3_600)
        let resumeAfterForwardJumpExpectation = self.expectation(description: "resumed samples collected after forward jump")
        resumeAfterForwardJumpExpectation.assertForOverFulfill = false
        collector.resume(sessionID: "session-clock-jumps")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resumeAfterForwardJumpExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — post-resume samples reflect the real (post-sleep) wall-clock time, not the pre-sleep
        // anchor lagging behind by ~1 hour. Pause again (flushing this batch) so we have a known
        // `flushedAfterForwardJump.timeseries.end` to check the next batch against below.
        let pauseAfterForwardJumpExpectation = self.expectation(description: "pause after forward jump settled")
        collector.pause(sessionID: "session-clock-jumps")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { pauseAfterForwardJumpExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let eventsAfterForwardJump = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        guard let flushedAfterForwardJump = eventsAfterForwardJump.last else {
            XCTFail("Expected at least one memory event with a sample after resume")
            return
        }
        let lastSampleDate = Date(timeIntervalSince1970: Double(flushedAfterForwardJump.timeseries.end) / 1_000_000_000)
        XCTAssertEqual(lastSampleDate.timeIntervalSince(clock.date), 0, accuracy: 1, "Post-resume sample should be anchored to the real post-sleep wall-clock time, not lag behind by the sleep duration")

        // When — the wall clock then moves backward by an hour while paused/backgrounded (e.g. an NTP
        // correction), then the collector resumes and samples again
        clock.date = clock.date.addingTimeInterval(-3_600)
        let resumeAfterBackwardJumpExpectation = self.expectation(description: "resumed samples collected after backward jump")
        resumeAfterBackwardJumpExpectation.assertForOverFulfill = false
        collector.resume(sessionID: "session-clock-jumps")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resumeAfterBackwardJumpExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-clock-jumps")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the post-resume batch must not precede the batch already flushed before the pause,
        // even though the wall clock moved backward while paused
        let allEvents = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        guard let resumedBatch = allEvents.last, allEvents.count > eventsAfterForwardJump.count else {
            XCTFail("Expected an additional memory event flushed after resume")
            return
        }
        XCTAssertGreaterThanOrEqual(
            resumedBatch.timeseries.start,
            flushedAfterForwardJump.timeseries.end,
            "Post-resume batch must not start before the batch already flushed prior to the pause"
        )
    }

    func testWhenPauseCalledBeforeStart_itIsNoOp() {
        // Given — collector not yet started
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )

        // When / Then — should not crash
        collector.pause(sessionID: "")
        collector.resume(sessionID: "")

        let settleExpectation = self.expectation(description: "settle")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { settleExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertTrue(featureScope.eventsWritten.isEmpty)
    }

    // MARK: - Common schema fields

    func testItPopulatesCommonSchemaFieldsFromContextAndConstructorInjectedDependencies() {
        // Given
        memoryReader.vitalData = 1_000_000
        let userInfo = UserInfo(id: "user-abc", name: "Jane", email: "jane@example.com", extraInfo: [:])
        let accountInfo = AccountInfo(id: "account-abc", name: "Acme", extraInfo: [:])
        let scope = FeatureScopeMock(
            context: .mockWith(
                buildNumber: "42",
                buildId: "build-abc",
                userInfo: userInfo,
                accountInfo: accountInfo,
                additionalContext: []
            )
        )
        let ciTest = RUMCITest(testExecutionId: "ci-exec-abc")
        let syntheticsTest = RUMSyntheticsTest(injected: nil, resultId: "synthetics-result", testId: "synthetics-test", syntheticsInfo: [:])
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            ciTest: ciTest,
            syntheticsTest: syntheticsTest
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-common", applicationID: "app-common", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-common")

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        let event = events[0]
        XCTAssertNotNil(event.device)
        XCTAssertNotNil(event.os)
        XCTAssertEqual(event.buildId, "build-abc")
        XCTAssertEqual(event.buildVersion, "42")
        XCTAssertEqual(event.ciTest?.testExecutionId, "ci-exec-abc")
        XCTAssertEqual(event.synthetics?.testId, "synthetics-test")
    }

    func testItNeverPopulatesPrivacySensitiveOrContextualFields() {
        // Given
        memoryReader.vitalData = 1_000_000
        let userInfo = UserInfo(id: "user-abc", name: "Jane", email: "jane@example.com", extraInfo: [:])
        let accountInfo = AccountInfo(id: "account-abc", name: "Acme", extraInfo: [:])
        let scope = FeatureScopeMock(
            context: .mockWith(
                userInfo: userInfo,
                accountInfo: accountInfo,
                additionalContext: [RUMCoreContext.mockAny()]
            )
        )
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(
            globalAttributes: ["custom-key": "custom-value"],
            activeView: (id: "view-abc", path: "/view/abc", name: "ViewController")
        )
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-privacy", applicationID: "app-privacy", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-privacy")

        // Then — these fields are never populated on timeseries events, regardless of available context
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        let event = events[0]
        XCTAssertNil(event.usr)
        XCTAssertNil(event.account)
        XCTAssertNil(event.context)
        XCTAssertNil(event.connectivity)
        XCTAssertNil(event.view)
        XCTAssertNil(event.tab)
        XCTAssertNil(event.stream)
        XCTAssertNil(event.display)
    }

    // MARK: - Timeseries range

    func testTimestampsAreMonotonicallyIncreasing() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        let expectation = self.expectation(description: "first batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-abc", applicationID: "app-123", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop(sessionID: "session-abc")

        // Then
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        guard let event = events.first else {
            XCTFail("Expected at least one memory event")
            return
        }
        let timestamps = event.timeseries.data.timestamps
        XCTAssertEqual(timestamps, timestamps.sorted(), "Timestamps should be monotonically increasing")
        XCTAssertEqual(event.timeseries.start, timestamps.first)
        XCTAssertEqual(event.timeseries.end, timestamps.last)
    }

    func testWhenWallClockJumpsBackwardMidSession_timestampsStayMonotonic() {
        // Given
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only `stop()` triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-clock-jump", applicationID: "app-1", sessionType: .user)

        let beforeJumpExpectation = self.expectation(description: "samples collected before the clock jump")
        beforeJumpExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { beforeJumpExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // When — the wall clock jumps backward (e.g. an NTP correction), but real time (and thus the
        // monotonic media clock the collector now anchors to) keeps moving forward normally
        clock.date = clock.date.addingTimeInterval(-60)
        clock.mediaTime.current += 0.2

        let afterJumpExpectation = self.expectation(description: "more samples collected after the clock jump")
        afterJumpExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { afterJumpExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop(sessionID: "session-clock-jump")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — sample timestamps are unaffected by the wall-clock jump and remain monotonically increasing
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        guard let event = events.first else {
            XCTFail("Expected at least one memory event")
            return
        }
        let timestamps = event.timeseries.data.timestamps
        XCTAssertEqual(timestamps, timestamps.sorted(), "Timestamps should stay monotonically increasing across a backward wall-clock jump")
        XCTAssertGreaterThanOrEqual(event.timeseries.end, event.timeseries.start, "The batch end must not precede its start")
    }

    // MARK: - Session lifetime self-enforcement

    func testWhenSessionExceedsMaxDuration_itSelfStopsAndFlushes() {
        // Given
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only self-expiry triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let startTime = clock.date
        let contextReader = RUMActiveContextReaderMock(sessionID: "session-expired", sessionStartTime: startTime, lastInteractionTime: startTime)
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-expired", applicationID: "app-1", sessionType: .user)

        let beforeExpiryExpectation = self.expectation(description: "samples collected before expiry")
        beforeExpiryExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { beforeExpiryExpectation.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Batch should not be flushed while the session is still within its max duration")

        // When — advance the (injected) clock and the activity reader's snapshot past the session's max
        // duration, mirroring how `Monitor` refreshes its snapshot on every processed command, without ever
        // calling stop() directly
        clock.advance(by: RUMSessionScope.Constants.sessionMaxDuration)
        contextReader.sessionActivity.lastInteractionTime = clock.date
        let selfStopExpectation = self.expectation(description: "self-stop settled")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { selfStopExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the buffered samples were flushed once the session exceeded max duration
        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected the collector to self-flush once the session exceeded max duration")
        let countAfterSelfStop = events.count

        // And — no further samples accumulate afterwards (the timer was cancelled)
        let settleExpectation = self.expectation(description: "no further samples after self-stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settleExpectation.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count, countAfterSelfStop, "No further batches should be written after self-stop")
    }

    func testWhenNoActivityWithinTimeoutWindow_itSelfStopsAndFlushes() {
        // Given
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only self-expiry triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let startTime = clock.date
        let contextReader = RUMActiveContextReaderMock(sessionID: "session-idle", sessionStartTime: startTime, lastInteractionTime: startTime)
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-idle", applicationID: "app-1", sessionType: .user)

        let beforeTimeoutExpectation = self.expectation(description: "samples collected before timeout")
        beforeTimeoutExpectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { beforeTimeoutExpectation.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty)

        // When — advance the clock past the inactivity timeout while the activity reader's `lastInteractionTime`
        // stays fixed at `startTime` (i.e. no RUM interaction was ever processed)
        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration)
        let selfStopExpectation = self.expectation(description: "self-stop settled")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { selfStopExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected the collector to self-flush once idle past the inactivity timeout")
    }

    func testWhenWallClockJumpsBackwardThenFreshInteractionArrives_doesNotFalselyExpireSession() {
        // Given — a backward wall-clock jump (e.g. NTP correction) happens mid-session, so the anchored
        // media-clock-derived date and the raw wall clock diverge
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // won't auto-flush — only self-expiry or `stop()` triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let startTime = clock.date
        let contextReader = RUMActiveContextReaderMock(sessionID: "session-clock-jump", sessionStartTime: startTime, lastInteractionTime: startTime)
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-clock-jump", applicationID: "app-1", sessionType: .user)

        // When — the wall clock jumps backward by more than the inactivity timeout, then a fresh interaction
        // is processed and reported at the new (earlier) wall-clock time, while the anchored/monotonic date
        // this collector would otherwise compare against keeps climbing on the old anchor
        clock.date = clock.date.addingTimeInterval(-RUMSessionScope.Constants.sessionTimeoutDuration - 60)
        clock.mediaTime.current += 0.2
        contextReader.sessionActivity.lastInteractionTime = clock.date

        let expectation = self.expectation(description: "still sampling after the jump and fresh interaction")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the session must not be treated as expired: the expiry check compares against `now()`
        // (the same wall-clock timeline `lastInteractionTime` lives on), not the sleep/adjustment-immune
        // anchored date, so a fresh interaction on the new wall-clock timeline keeps the session alive
        XCTAssertTrue(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Session must not be treated as expired by a stale comparison between the anchored date and the fresh wall-clock interaction")
        collector.stop(sessionID: "session-clock-jump")
    }

    func testWhenActivityReaderReportsRecentInteraction_preventsSelfStopWithinTimeoutWindow() {
        // Given
        memoryReader.vitalData = 1_000_000
        let clock = MutableClock()
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000,
            now: clock.now,
            mediaTimeProvider: clock.mediaTime
        )
        let startTime = clock.date
        let contextReader = RUMActiveContextReaderMock(sessionID: "session-active", sessionStartTime: startTime, lastInteractionTime: startTime)
        collector.activeContextReader = contextReader
        collector.start(sessionID: "session-active", applicationID: "app-1", sessionType: .user)

        // When — a RUM interaction is reported right before what would have been the inactivity timeout,
        // resetting the clock the reader exposes to `sample()`
        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)
        contextReader.sessionActivity.lastInteractionTime = clock.date
        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)

        let expectation = self.expectation(description: "still sampling")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — sampling continued since the reader's last interaction time reset the inactivity clock before it lapsed
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected sampling to continue since activity reset the inactivity clock")
        collector.stop(sessionID: "session-active")
    }

    // MARK: - Session-ID guard against stale calls

    func testStaleStopCall_afterNewSessionStarted_doesNotStopNewSession() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        collector.start(sessionID: "session-old", applicationID: "app-1", sessionType: .user)
        collector.start(sessionID: "session-new", applicationID: "app-1", sessionType: .user)

        // When — a stale stop() call for the already-replaced session arrives
        collector.stop(sessionID: "session-old")

        // Then — sampling for the new session continues uninterrupted
        let expectation = self.expectation(description: "new session still sampling")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 2)

        let events = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected the new session to keep sampling despite a stale stop() call for the old session")
        XCTAssertEqual(events.last?.session.id, "session-new")
        collector.stop(sessionID: "session-new")
    }

    func testStalePauseCall_afterNewSessionStarted_doesNotPauseNewSession() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock()
        collector.activeContextReader = contextReader

        collector.start(sessionID: "session-old", applicationID: "app-1", sessionType: .user)
        collector.start(sessionID: "session-new", applicationID: "app-1", sessionType: .user)

        // When — a stale pause() call for the already-replaced session arrives
        collector.pause(sessionID: "session-old")

        // Then — the new session keeps sampling, unaffected
        let expectation = self.expectation(description: "new session still sampling despite stale pause")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty, "Expected sampling to continue since the stale pause() targeted a different session")
        collector.stop(sessionID: "session-new")
    }
}

private class RUMActiveContextReaderMock: RUMActiveContextReader {
    var globalAttributes: [AttributeKey: AttributeValue]
    var activeView: (id: String?, path: String?, name: String?)
    var sessionActivity: (sessionID: String?, sessionStartTime: Date?, lastInteractionTime: Date?)
    var hasReplay: Bool?

    init(
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        activeView: (id: String?, path: String?, name: String?) = (.mockAny(), .mockAny(), nil),
        sessionID: String? = nil,
        sessionStartTime: Date? = nil,
        lastInteractionTime: Date? = nil,
        hasReplay: Bool? = nil
    ) {
        self.globalAttributes = globalAttributes
        self.activeView = activeView
        self.sessionActivity = (sessionID, sessionStartTime, lastInteractionTime)
        self.hasReplay = hasReplay
    }

    func isSessionExpired(sessionID: String, at date: Date) -> Bool {
        guard sessionActivity.sessionID == sessionID,
              let sessionStartTime = sessionActivity.sessionStartTime,
              let lastInteractionTime = sessionActivity.lastInteractionTime else {
            return false
        }
        return RUMSessionScope.hasExpired(sessionStartTime: sessionStartTime, currentTime: date)
            || RUMSessionScope.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: date)
    }
}

/// A `Date` provider whose current time can be advanced manually, used to deterministically test the
/// collector's self-enforced session expiry without waiting on real wall-clock durations.
///
/// Carries a paired `mediaTime` (`MediaTimeProviderMock`), settable independently of `date`, since
/// `TimeseriesSessionCollector` derives sample timestamps from an anchor plus elapsed monotonic media time
/// (not `now()` directly) after session start — tests that simulate elapsed time must advance `mediaTime`
/// alongside `date` to keep the two consistent, and tests exercising a wall-clock/media-clock divergence
/// (e.g. a backward wall-clock jump) can advance them independently.
private class MutableClock {
    var date: Date
    let mediaTime = MediaTimeProviderMock()

    init(date: Date = Date()) {
        self.date = date
    }

    func now() -> Date { date }

    /// Advances both `date` and `mediaTime` by the same delta, as real elapsed time would.
    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
        mediaTime.current += interval
    }
}

#endif
