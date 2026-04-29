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
            cpuUsageProvider: { nil },
            compressionSampler: { false }
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
            cpuUsageProvider: { 42.5 },
            compressionSampler: { false }
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
            cpuUsageProvider: { nil },
            compressionSampler: { false }
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
            cpuUsageProvider: { 10.0 },
            compressionSampler: { false }
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
            cpuUsageProvider: { nil },
            compressionSampler: { false }
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

    // MARK: - Schema coin flip

    func testWhenDeltaCompressionSampled_itWritesDeltaEventForMemory() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            compressionSampler: { true }
        )

        let expectation = self.expectation(description: "memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-delta", applicationID: "app-delta", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — AnyEncodable delta-object event written, no typed object event
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertTrue(typedEvents.isEmpty, "Object-schema typed event must not be written when delta is sampled")

        let anyEncodableEvents = featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }
        XCTAssertFalse(anyEncodableEvents.isEmpty, "Expected delta-schema AnyEncodable event")

        let jsonData = try! JSONEncoder().encode(anyEncodableEvents[0])
        let dict = try! XCTUnwrap(try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let tsDict = try! XCTUnwrap(dict["timeseries"] as? [String: Any])
        XCTAssertEqual(tsDict["schema"] as? String, "delta-object")
        let dataDict = try! XCTUnwrap(tsDict["data"] as? [String: Any])
        XCTAssertNotNil(dataDict["ts"])
        XCTAssertNotNil(dataDict["memory_max"])
        XCTAssertNotNil(dataDict["memory_percent"])
    }

    func testWhenObjectSchemaSampled_itWritesObjectEventForMemory() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            compressionSampler: { false }
        )

        let expectation = self.expectation(description: "memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-object", applicationID: "app-object", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — typed object event written, no AnyEncodable delta event
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(typedEvents.isEmpty, "Expected object-schema typed memory event")
        XCTAssertEqual(typedEvents[0].timeseries.schema, .object)
        XCTAssertTrue(featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }.isEmpty)
    }

    func testWhenDeltaCompressionSampled_itWritesDeltaEventForCPU() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { 50.0 },
            compressionSampler: { true }
        )

        let expectation = self.expectation(description: "cpu batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-delta-cpu", applicationID: "app-delta", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — AnyEncodable delta-scalar event written, no typed object event
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)
        XCTAssertTrue(typedEvents.isEmpty, "Object-schema typed event must not be written when delta is sampled")

        let anyEncodableEvents = featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }
        XCTAssertFalse(anyEncodableEvents.isEmpty, "Expected delta-schema AnyEncodable event")

        let jsonData = try! JSONEncoder().encode(anyEncodableEvents[0])
        let dict = try! XCTUnwrap(try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let tsDict = try! XCTUnwrap(dict["timeseries"] as? [String: Any])
        XCTAssertEqual(tsDict["schema"] as? String, "delta-scalar")
        let dataDict = try! XCTUnwrap(tsDict["data"] as? [String: Any])
        XCTAssertNotNil(dataDict["ts"])
        XCTAssertNotNil(dataDict["value"])
    }

    func testWhenObjectSchemaSampled_itWritesObjectEventForCPU() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { 50.0 },
            compressionSampler: { false }
        )

        let expectation = self.expectation(description: "cpu batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-object-cpu", applicationID: "app-object", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — typed object event written, no AnyEncodable delta event
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)
        XCTAssertFalse(typedEvents.isEmpty, "Expected object-schema typed CPU event")
        XCTAssertEqual(typedEvents[0].timeseries.schema, .object)
        XCTAssertTrue(featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }.isEmpty)
    }

    func testWhenDeltaCompressionSampledWithSingleSample_itFallsBackToObjectEvent() {
        // Given — delta sampled but only 1 sample: DeltaEncoder returns nil, falls back to object
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil },
            compressionSampler: { true }
        )

        let expectation = self.expectation(description: "one sample collected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { expectation.fulfill() }
        collector.start(sessionID: "session-fallback", applicationID: "app-fallback", sessionType: .user)
        waitForExpectations(timeout: 2)

        let stopExpectation = self.expectation(description: "stop completed")
        collector.stop()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { stopExpectation.fulfill() }
        waitForExpectations(timeout: 2)

        // Then — falls back to object event, no AnyEncodable
        XCTAssertFalse(featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty)
        XCTAssertTrue(featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }.isEmpty)
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
            cpuUsageProvider: { nil },
            compressionSampler: { false }
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
