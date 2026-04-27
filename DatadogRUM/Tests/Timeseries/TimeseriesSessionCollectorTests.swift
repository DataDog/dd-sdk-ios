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

    // MARK: - Dual-flush (object + delta)

    func testFlushWritesBothObjectAndDeltaEventsForMemory() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
        )

        // When
        let expectation = self.expectation(description: "memory batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-dual", applicationID: "app-dual", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — both a typed object event and an AnyEncodable delta event are written
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self)
        XCTAssertFalse(typedEvents.isEmpty, "Expected object-schema memory events")
        XCTAssertEqual(typedEvents[0].timeseries.schema, .object)

        let rawEvents = featureScope.eventsWritten
        let anyEncodableEvents = rawEvents.compactMap { $0 as? AnyEncodable }
        XCTAssertFalse(anyEncodableEvents.isEmpty, "Expected delta-schema AnyEncodable event")

        let jsonData = try! JSONEncoder().encode(anyEncodableEvents[0])
        let dict = try! XCTUnwrap(try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let tsDict = try! XCTUnwrap(dict["timeseries"] as? [String: Any])

        XCTAssertEqual(tsDict["schema"] as? String, "delta-object")

        let dataDict = try! XCTUnwrap(tsDict["data"] as? [String: Any])
        XCTAssertNotNil(dataDict["precision"], "Delta payload must contain 'precision'")
        XCTAssertNotNil(dataDict["ts"], "Delta payload must contain 'ts'")
        XCTAssertNotNil(dataDict["memory_max"], "Delta payload must contain 'memory_max'")
        XCTAssertNotNil(dataDict["memory_percent"], "Delta payload must contain 'memory_percent'")
    }

    func testFlushWritesBothObjectAndDeltaEventsForCPU() {
        // Given
        memoryReader.vitalData = nil
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 3,
            samplingInterval: 0.05,
            cpuUsageProvider: { 50.0 }
        )

        // When
        let expectation = self.expectation(description: "cpu batch written")
        expectation.assertForOverFulfill = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }

        collector.start(sessionID: "session-dual-cpu", applicationID: "app-dual", sessionType: .user)
        waitForExpectations(timeout: 2)
        collector.stop()

        // Then — both a typed object event and an AnyEncodable delta event are written
        let typedEvents = featureScope.eventsWritten(ofType: RUMTimeseriesCpuEvent.self)
        XCTAssertFalse(typedEvents.isEmpty, "Expected object-schema CPU events")
        XCTAssertEqual(typedEvents[0].timeseries.schema, .object)

        let rawEvents = featureScope.eventsWritten
        let anyEncodableEvents = rawEvents.compactMap { $0 as? AnyEncodable }
        XCTAssertFalse(anyEncodableEvents.isEmpty, "Expected delta-schema AnyEncodable event")

        let jsonData = try! JSONEncoder().encode(anyEncodableEvents[0])
        let dict = try! XCTUnwrap(try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let tsDict = try! XCTUnwrap(dict["timeseries"] as? [String: Any])

        XCTAssertEqual(tsDict["schema"] as? String, "delta-scalar")

        let dataDict = try! XCTUnwrap(tsDict["data"] as? [String: Any])
        XCTAssertNotNil(dataDict["precision"], "Delta payload must contain 'precision'")
        XCTAssertNotNil(dataDict["ts"], "Delta payload must contain 'ts'")
        XCTAssertNotNil(dataDict["value"], "Delta payload must contain 'value'")
    }

    func testSingleSampleBatchWritesObjectEventButNoDeltaEvent() {
        // Given
        memoryReader.vitalData = 1_000_000
        let collector = TimeseriesSessionCollector(
            memoryReader: memoryReader,
            featureScope: featureScope,
            batchSize: 100, // large batch — won't auto-flush
            samplingInterval: 0.05,
            cpuUsageProvider: { nil }
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

        // Then — object event is written, but DeltaEncoder requires >1 samples so no delta event
        XCTAssertFalse(
            featureScope.eventsWritten(ofType: RUMTimeseriesMemoryEvent.self).isEmpty,
            "Object-schema event should be written even for a single sample"
        )
        let anyEncodableEvents = featureScope.eventsWritten.compactMap { $0 as? AnyEncodable }
        XCTAssertTrue(anyEncodableEvents.isEmpty, "Delta event must not be written for a single-sample batch")
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
