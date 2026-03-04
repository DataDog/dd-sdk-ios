/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Timeseries event structure for performance metrics.
///
/// Phase 2: Backend-aligned schema (session-scoped, explicit timestamps, snake_case naming).
/// This model matches the schema agreed with backend team and enabled in staging.
internal struct TimeseriesEvent: Encodable {
    /// Event type identifier.
    let type: String = "timeseries"

    /// Unique identifier for this timeseries event.
    let id: String

    /// Application identifier.
    let applicationId: String

    /// Session identifier.
    let sessionId: String

    /// Timestamp of first data point (nanoseconds from epoch).
    let start: Int64

    /// Timestamp of last data point (nanoseconds from epoch).
    let end: Int64

    /// Timeseries name (snake_case enum).
    /// Examples: memory_usage, battery_level, disk_writes_bytes, thread_count
    let name: String

    /// Array of timestamped data points.
    let data: [DataPoint]

    /// Single data point with timestamp and value.
    struct DataPoint: Encodable {
        /// Timestamp in nanoseconds from epoch (UTC).
        let timestamp: Int64

        /// Metric value.
        let dataPointValue: Double

        enum CodingKeys: String, CodingKey {
            case timestamp
            case dataPointValue = "data_point_value"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case applicationId = "application_id"
        case sessionId = "session_id"
        case start
        case end
        case name
        case data
    }
}

/// Factory for creating timeseries events from collected samples.
internal struct TimeseriesEventBuilder {
    /// Creates a timeseries event from memory samples.
    ///
    /// - Parameters:
    ///   - samples: Array of (timestamp in ms, footprint in bytes) tuples
    ///   - sessionID: RUM session identifier
    ///   - applicationID: Application identifier
    ///   - batchSize: Maximum number of data points per event (configurable for staging)
    /// - Returns: Array of TimeseriesEvent (multiple if samples exceed batchSize)
    static func createEvents(
        from samples: [(timestamp: Int64, footprint: UInt64)],
        sessionID: RUMUUID,
        applicationID: String,
        batchSize: Int = 120
    ) -> [TimeseriesEvent] {
        // TODO: Implement batching logic
        // For Phase 2: Create single event with all samples (up to batchSize)
        // Future: Support multiple events if samples.count > batchSize

        guard !samples.isEmpty else { return [] }

        // Take first batchSize samples
        let batchSamples = Array(samples.prefix(batchSize))

        // Convert to data points (milliseconds → nanoseconds)
        let dataPoints = batchSamples.map { sample in
            TimeseriesEvent.DataPoint(
                timestamp: sample.timestamp * 1_000_000, // ms → ns
                dataPointValue: Double(sample.footprint)
            )
        }

        let event = TimeseriesEvent(
            id: UUID().uuidString,
            applicationId: applicationID,
            sessionId: sessionID.rawValue.uuidString,
            start: dataPoints.first!.timestamp,
            end: dataPoints.last!.timestamp,
            name: "memory_usage",
            data: dataPoints
        )

        return [event]
    }
}
