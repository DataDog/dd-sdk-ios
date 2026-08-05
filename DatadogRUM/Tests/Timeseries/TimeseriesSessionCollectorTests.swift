/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import TestUtilities
import DatadogInternal
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
        collector.stop()

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
        collector.stop()

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
        collector.stop()

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
        collector.stop()

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
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].source, .reactNative)
    }

    func testWhenActiveViewExists_itAttachesViewToEvent() {
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
        let contextReader = RUMActiveContextReaderMock(activeView: (id: "view-abc", path: "/view/abc", name: nil))
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-view", applicationID: "app-view", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].view?.id, "view-abc")
        XCTAssertEqual(events[0].view?.url, "/view/abc")
    }

    func testWhenActiveViewHasName_itAttachesViewNameToEvent() {
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

        collector.start(sessionID: "session-view-name", applicationID: "app-view-name", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].view?.name, "ViewController")
    }

    func testWhenSessionReplayHasReplay_itAttachesHasReplayToEvent() {
        // Given
        memoryReader.vitalData = 1_000_000
        let hasReplay = SessionReplayCoreContext.HasReplay(value: true)
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [hasReplay]))
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

        collector.start(sessionID: "session-has-replay", applicationID: "app-has-replay", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
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
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].dd.configuration?.sessionSampleRate, 42)
    }

    func testWhenViewEndsRightBeforeFlush_itStillAttachesTheViewSamplesWereCollectedUnder() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: []))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 100, // won't auto-flush — only the explicit stop() below triggers the flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            totalRAM: 4_000_000_000
        )
        let contextReader = RUMActiveContextReaderMock(activeView: (id: "view-ending", path: "/view/ending", name: nil))
        collector.activeContextReader = contextReader

        // When — samples are collected while a view is active
        let expectation = self.expectation(description: "samples collected under an active view")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        collector.start(sessionID: "session-ending-view", applicationID: "app-ending-view", sessionType: .user)
        waitForExpectations(timeout: 2)

        // The view ends right before the batch is flushed
        contextReader.activeView = (nil, nil, nil)

        let syncExpectation = self.expectation(description: "stop completed")
        collector.stop()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { syncExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — the batch is still written, attributed to the view it was actually collected under
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty, "Expected the batch collected under an active view to be flushed, not dropped")
        XCTAssertEqual(events[0].view?.id, "view-ending")
        XCTAssertEqual(events[0].view?.url, "/view/ending")
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
        collector.stop()

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
        collector.stop()
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
        collector.stop()
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
        collector.stop()
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
        collector.stop()

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
        collector.stop()
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
        collector.pause()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { pauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — pause() flushes the partial buffer; no further events written
        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertGreaterThanOrEqual(countAfterPause, countBeforePause, "pause() must not drop buffered data")

        let countAfterSettle = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertEqual(countAfterPause, countAfterSettle, "No further events should be written while paused")
        collector.stop()
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
        collector.pause()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { pauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count

        // When — resume and let samples accumulate
        let resumeExpectation = self.expectation(description: "resumed samples collected")
        resumeExpectation.assertForOverFulfill = false
        collector.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resumeExpectation.fulfill() }
        waitForExpectations(timeout: 2)
        collector.stop()

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
        collector.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { afterPauseExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — no new events accumulate while paused
        let countAfterPause = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).count
        XCTAssertEqual(countAfterPause, countBeforePause, "Sampling should stop while backgrounded, regardless of trackBackgroundEvents")
        collector.stop()
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
        collector.pause()
        collector.resume()

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
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        let event = events[0]
        XCTAssertEqual(event.usr?.id, "user-abc")
        XCTAssertEqual(event.account?.id, "account-abc")
        XCTAssertNotNil(event.connectivity)
        XCTAssertNotNil(event.device)
        XCTAssertNotNil(event.os)
        XCTAssertEqual(event.buildId, "build-abc")
        XCTAssertEqual(event.buildVersion, "42")
        XCTAssertEqual(event.ciTest?.testExecutionId, "ci-exec-abc")
        XCTAssertEqual(event.synthetics?.testId, "synthetics-test")
    }

    func testItPopulatesContextFromActiveContextReader() {
        // Given
        memoryReader.vitalData = 1_000_000
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: []))
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: scope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )
        let contextReader = RUMActiveContextReaderMock(globalAttributes: ["custom-key": "custom-value"])
        collector.activeContextReader = contextReader

        // When
        let expectation = self.expectation(description: "batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-context", applicationID: "app-context", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then
        let events = scope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].context?.contextInfo["custom-key"] as? String, "custom-value")
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
        collector.stop()

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
}

private class RUMActiveContextReaderMock: RUMActiveContextReader {
    var globalAttributes: [AttributeKey: AttributeValue]
    var activeView: (id: String?, path: String?, name: String?)

    init(
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        activeView: (id: String?, path: String?, name: String?) = (.mockAny(), .mockAny(), nil)
    ) {
        self.globalAttributes = globalAttributes
        self.activeView = activeView
    }
}

#endif
