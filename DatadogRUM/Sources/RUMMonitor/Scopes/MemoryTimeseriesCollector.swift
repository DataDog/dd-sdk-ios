/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Collects memory footprint timeseries data at regular intervals for RUM sessions.
///
/// Phase 1 prototype: Session-scoped memory collection at 1-second intervals.
/// This collector samples physical memory footprint using VitalMemoryReader and stores
/// timestamped data points in a thread-safe buffer for later processing.
internal class MemoryTimeseriesCollector {
    /// The session ID this collector is associated with.
    private let sessionID: RUMUUID

    /// The application ID for event creation.
    private let applicationID: String

    /// Batch size for event creation (configurable for staging validation).
    private let batchSize: Int

    /// Reader for memory footprint data.
    private let memoryReader: VitalMemoryReader

    /// Background queue for collection timer.
    private let collectionQueue: DispatchQueue

    /// Serial queue for thread-safe buffer access.
    private let bufferQueue: DispatchQueue

    /// Timer for periodic memory sampling.
    private var timer: DispatchSourceTimer?

    /// Buffer storing timestamped memory samples.
    /// - Note: Tuple format: (timestamp in milliseconds, footprint in bytes)
    private var samples: [(timestamp: Int64, footprint: UInt64)] = []

    /// Track number of failed reads for telemetry (Phase 3).
    private var failedReadCount: Int = 0

    /// Initializes a new memory timeseries collector.
    ///
    /// - Parameters:
    ///   - sessionID: The RUM session ID to associate collected data with.
    ///   - applicationID: The application ID for event creation.
    ///   - batchSize: Batch size for event creation (configurable for staging validation). Defaults to 120 (2 minutes at 1Hz).
    ///   - reader: The memory reader to use for sampling. Defaults to VitalMemoryReader.
    init(
        sessionID: RUMUUID,
        applicationID: String,
        batchSize: Int = 120,
        reader: VitalMemoryReader = VitalMemoryReader()
    ) {
        self.sessionID = sessionID
        self.applicationID = applicationID
        self.batchSize = batchSize
        self.memoryReader = reader
        self.collectionQueue = DispatchQueue(
            label: "com.datadoghq.memory-timeseries",
            target: .global(qos: .userInitiated)
        )
        self.bufferQueue = DispatchQueue(
            label: "com.datadoghq.memory-timeseries-buffer",
            target: .global(qos: .userInitiated)
        )
    }

    /// Starts memory collection.
    ///
    /// Begins periodic sampling at 1-second intervals. Collection runs on a background
    /// utility queue and does not impact main thread performance.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: collectionQueue)

        // Schedule with 1-second interval and 100ms tolerance for power efficiency
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))

        timer.setEventHandler { [weak self] in
            self?.collectSample()
        }

        self.timer = timer
        timer.resume()

        DD.logger.debug("MemoryTimeseriesCollector started for session \(sessionID.rawValue)")
    }

    /// Stops memory collection.
    ///
    /// Cancels the collection timer and stops sampling. The buffer is preserved
    /// for Phase 3 processing.
    func stop() {
        timer?.cancel()
        timer = nil

        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            // Log final state
            DD.logger.debug("""
                MemoryTimeseriesCollector stopped for session \(self.sessionID.rawValue). \
                Total samples: \(self.samples.count), Failed reads: \(self.failedReadCount)
                """)

            // Create final events (for verification)
            let events = TimeseriesEventBuilder.createEvents(
                from: self.samples,
                sessionID: self.sessionID,
                applicationID: self.applicationID,
                batchSize: self.batchSize
            )

            DD.logger.debug("""
                Final event summary: \(events.count) event(s) created. \
                First event: \(events.first?.data.count ?? 0) data points
                """)
        }
    }

    /// Creates and sends timeseries events from buffered samples.
    ///
    /// Validation checklist (for staging):
    /// - [ ] JSON uses snake_case (session_id, application_id, data_point_value)
    /// - [ ] Timestamps are in nanoseconds
    /// - [ ] Event has session_id and application_id (NOT view.id)
    /// - [ ] name field uses snake_case (memory_usage not memory.usage)
    /// - [ ] data array contains timestamp + data_point_value per point
    /// - [ ] Event type is "timeseries"
    ///
    /// - Parameters:
    ///   - writer: Writer for sending events to DatadogCore
    /// - Returns: Number of events sent.
    func flushEvents(writer: Writer) -> Int {
        var eventCount = 0

        bufferQueue.sync {
            guard !samples.isEmpty else { return }

            // Only flush if we have enough samples for at least one batch
            guard samples.count >= batchSize else { return }

            // Create events
            let events = TimeseriesEventBuilder.createEvents(
                from: samples,
                sessionID: sessionID,
                applicationID: applicationID,
                batchSize: batchSize
            )

            DD.logger.debug("MemoryTimeseriesCollector: Created \(events.count) timeseries event(s)")
            logEventDetails(events)

            // Send events to DatadogCore
            for event in events {
                writer.write(value: event)
                eventCount += 1

                DD.logger.debug("""
                    Timeseries event sent:
                      ID: \(event.id)
                      Session: \(event.sessionId)
                      Data points: \(event.data.count)
                    """)
            }

            // Clear buffer after successful flush
            if eventCount > 0 {
                samples.removeAll()
                DD.logger.debug("Buffer cleared after sending \(eventCount) event(s)")
            }

            // Log staging verification data
            DD.logger.debug("""
                ========================================
                STAGING VERIFICATION DATA
                ========================================
                Events sent: \(eventCount)
                Session ID: \(sessionID.rawValue)
                Application ID: \(applicationID)

                To verify in staging:
                1. Query events by session_id: \(sessionID.rawValue)
                2. Expected event count: \(eventCount)
                3. Check event name: memory_usage
                4. Verify data points count: ~\(batchSize) per event

                Query example:
                SELECT * FROM timeseries_events
                WHERE session_id = '\(sessionID.rawValue)'
                ORDER BY start
                ========================================
                """)
        }

        return eventCount
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Private

    /// Checks if buffer should be flushed (batch size reached).
    ///
    /// - Returns: True if buffer has at least batchSize samples ready to flush.
    func shouldFlush() -> Bool {
        var result = false
        bufferQueue.sync {
            result = samples.count >= batchSize
        }
        return result
    }

    /// Collects a single memory sample.
    ///
    /// Reads current memory footprint and stores it with a timestamp in the buffer.
    /// Runs on the collection queue.
    private func collectSample() {
        // Read current memory footprint
        guard let footprint = memoryReader.readVitalData() else {
            // Log error and skip sample per Phase 1 constraints
            DD.logger.error("Failed to read memory footprint via task_info")

            bufferQueue.async { [weak self] in
                self?.failedReadCount += 1
            }
            // TODO: Phase 3 - Send telemetry to track failure rates
            return
        }

        // Convert timestamp to milliseconds (SDK standard)
        let timestampMs = Date().timeIntervalSince1970.dd.toInt64Milliseconds

        // Store sample in thread-safe buffer
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            self.samples.append((timestamp: timestampMs, footprint: UInt64(footprint)))

            // Log when batch size reached (ready to flush)
            if self.samples.count == self.batchSize {
                DD.logger.debug("MemoryTimeseriesCollector: Batch size reached (\(self.batchSize) samples). Ready to flush.")
            }

            // Log batch snapshots every 120 samples (~2 minutes at 1/sec)
            if self.samples.count % 120 == 0 {
                self.logBatchSnapshot()
            }
        }
    }

    /// Logs metadata about the current batch of samples.
    ///
    /// Provides validation data and real sample statistics for Phase 2 schema decisions.
    /// Runs on the buffer queue.
    private func logBatchSnapshot() {
        guard !samples.isEmpty else { return }

        let count = samples.count
        let firstTimestamp = samples.first!.timestamp
        let lastTimestamp = samples.last!.timestamp
        let estimatedSizeBytes = count * 16 // 8 bytes timestamp + 8 bytes footprint

        let footprints = samples.map { $0.footprint }
        let minFootprint = footprints.min() ?? 0
        let maxFootprint = footprints.max() ?? 0
        let avgFootprint = footprints.reduce(0, +) / UInt64(footprints.count)

        // Preview event creation
        let wouldCreateEvents = (count + batchSize - 1) / batchSize

        DD.logger.debug("""
            Memory timeseries batch snapshot:
              Session: \(sessionID.rawValue)
              Samples: \(count)
              Timestamp range: \(firstTimestamp) - \(lastTimestamp) (\((lastTimestamp - firstTimestamp) / 1000)s)
              Estimated size: \(estimatedSizeBytes) bytes
              Memory footprint: min=\(minFootprint) bytes, max=\(maxFootprint) bytes, avg=\(avgFootprint) bytes
              Would create: \(wouldCreateEvents) event(s) with batch size \(batchSize)
            """)
    }

    /// Logs detailed event information for debugging and validation.
    ///
    /// - Parameter events: Events to inspect
    private func logEventDetails(_ events: [TimeseriesEvent]) {
        for (index, event) in events.enumerated() {
            let dataCount = event.data.count
            let firstTimestamp = event.data.first?.timestamp ?? 0
            let lastTimestamp = event.data.last?.timestamp ?? 0
            let durationMs = (lastTimestamp - firstTimestamp) / 1_000_000 // ns → ms

            let firstValue = event.data.first?.dataPointValue ?? 0
            let lastValue = event.data.last?.dataPointValue ?? 0
            let avgValue = event.data.map { $0.dataPointValue }.reduce(0, +) / Double(dataCount)

            DD.logger.debug("""
                Timeseries Event [\(index + 1)/\(events.count)]:
                  Type: \(event.type)
                  ID: \(event.id)
                  Name: \(event.name)
                  Session: \(event.sessionId)
                  Application: \(event.applicationId)
                  Duration: \(durationMs)ms
                  Data points: \(dataCount)
                  Value range: \(Int(firstValue)) → \(Int(lastValue)) bytes (avg: \(Int(avgValue)))
                  Start timestamp: \(firstTimestamp) ns
                  End timestamp: \(lastTimestamp) ns
                """)

            // Sample first 3 data points for validation
            if dataCount > 0 {
                let samplePoints = event.data.prefix(3)
                DD.logger.debug("""
                  Sample data points:
                  \(samplePoints.map { "  [\($0.timestamp)]: \(Int($0.dataPointValue)) bytes" }.joined(separator: "\n"))
                  """)
            }
        }
    }
}
