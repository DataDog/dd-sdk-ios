/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class TimeseriesSessionCollectorTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private let memoryReader = SamplingBasedVitalReaderMock()

    // MARK: - Memory events

    func testWhenBatchSizeIsReached_itWritesMemoryEvent() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 2,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )

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
        XCTAssertEqual(event.timeseries.data.count, 2)
        XCTAssertEqual(event.timeseries.data[0].dataPoint.memoryMax, 1_000_000)
        XCTAssertGreaterThan(event.timeseries.data[0].dataPoint.memoryPercent, 0)
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
        XCTAssertEqual(event.timeseries.data.count, 2)
        XCTAssertEqual(event.timeseries.data[0].dataPoint.cpuUsage, 42.5)
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

    func testWhenStartIsCalledAgain_itUsesNewSessionMetadata() {
        // Given
        memoryReader.vitalData = 512_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )

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
        let lastEvent = try! XCTUnwrap(events.last)
        XCTAssertEqual(lastEvent.session.id, "session-2")
    }

    // MARK: - Delta compression

    func testWhenDeltaCompressionEnabled_itWritesDeltaShapedEvent() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            enableDeltaCompression: true
        )

        // When
        let expectation = self.expectation(description: "delta memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-delta", applicationID: "app-delta", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — written events are AnyEncodable (not RUMTimeseriesMemoryEvent)
        XCTAssertTrue(
            featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty,
            "Delta mode should not write typed RUMTimeseriesMemoryEvent"
        )

        let rawEvents = featureScope.eventsWritten
        XCTAssertFalse(rawEvents.isEmpty, "Expected at least one delta event to be written")

        guard let anyEncodable = rawEvents.first as? AnyEncodable else {
            XCTFail("Expected AnyEncodable event, got \(type(of: rawEvents.first))")
            return
        }

        let jsonData = try! JSONEncoder().encode(anyEncodable)
        let dict = try! XCTUnwrap(try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let tsDict = try! XCTUnwrap(dict["timeseries"] as? [String: Any])
        let dataDict = try! XCTUnwrap(tsDict["data"] as? [String: Any])

        XCTAssertNotNil(dataDict["precision"], "Delta payload must contain 'precision'")
        XCTAssertNotNil(dataDict["ts"], "Delta payload must contain 'ts'")
        XCTAssertNotNil(dataDict["memory_max"], "Delta payload must contain 'memory_max'")
        XCTAssertNotNil(dataDict["memory_percent"], "Delta payload must contain 'memory_percent'")
    }

    func testWhenDeltaCompressionEnabled_singleSampleBatchIsDropped() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // large batch — won't auto-flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            enableDeltaCompression: true
        )

        // When — collect exactly one sample then stop
        let expectation = self.expectation(description: "one sample collected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { expectation.fulfill() }

        collector.start(sessionID: "session-single", applicationID: "app-single", sessionType: .user)
        waitForExpectations(timeout: 2)

        let stopExpectation = self.expectation(description: "stop completed")
        collector.stop()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { stopExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — single-sample batches are dropped by DeltaEncoder
        XCTAssertTrue(featureScope.eventsWritten.isEmpty, "Single-sample batch must be dropped in delta mode")
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
        let timestamps = event.timeseries.data.map { $0.timestamp }
        XCTAssertEqual(timestamps, timestamps.sorted(), "Timestamps should be monotonically increasing")
        XCTAssertEqual(event.timeseries.start, timestamps.first)
        XCTAssertEqual(event.timeseries.end, timestamps.last)
    }
}
