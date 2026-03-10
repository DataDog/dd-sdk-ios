/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// Phase 02.1: Timeseries events now use RUMTimeseriesEvent from RUMDataModels.swift
// This follows the standard RUM event pattern with RUM common properties and nested timeseries object.

/// Factory for creating timeseries events from collected samples.
internal struct TimeseriesEventBuilder {
    /// Creates a timeseries event from memory samples.
    ///
    /// - Parameters:
    ///   - samples: Array of (timestamp in ms, footprint in bytes) tuples
    ///   - sessionID: RUM session identifier
    ///   - applicationID: Application identifier
    ///   - date: Event date in ms from epoch
    ///   - batchSize: Maximum number of data points per event (configurable for staging)
    ///   - service: Service name from DatadogContext
    ///   - version: App version from DatadogContext
    /// - Returns: Array of RUMTimeseriesEvent (multiple if samples exceed batchSize)
    /// - Note: Event start/end are in milliseconds; data point timestamps are in nanoseconds
    static func createEvents(
        from samples: [(timestamp: Int64, footprint: UInt64)],
        sessionID: RUMUUID,
        applicationID: String,
        date: Int64,
        batchSize: Int = 120,
        service: String? = nil,
        version: String? = nil
    ) -> [RUMTimeseriesEvent] {
        // TODO: Implement batching logic
        // For Phase 2: Create single event with all samples (up to batchSize)
        // Future: Support multiple events if samples.count > batchSize

        guard !samples.isEmpty else { return [] }

        // Take first batchSize samples
        let batchSamples = Array(samples.prefix(batchSize))

        // Convert to data points (milliseconds → nanoseconds)
        let dataPoints = batchSamples.map { sample in
            RUMTimeseriesEvent.Timeseries.DataPoint(
                dataPointValue: Double(sample.footprint),
                timestamp: sample.timestamp * 1_000_000 // ms → ns
            )
        }

        // Get start/end in milliseconds from original samples (not converted data points)
        let startMs = batchSamples.first!.timestamp
        let endMs = batchSamples.last!.timestamp

        let timeseries = RUMTimeseriesEvent.Timeseries(
            data: dataPoints,
            end: endMs,  // milliseconds (RUM common schema)
            id: UUID().uuidString.lowercased(),
            name: .memoryUsage,
            start: startMs  // milliseconds (RUM common schema)
        )

        let event = RUMTimeseriesEvent(
            dd: RUMTimeseriesEvent.DD(),
            application: RUMTimeseriesEvent.Application(id: applicationID),
            date: date,
            service: service,
            session: RUMTimeseriesEvent.Session(
                id: sessionID.toRUMDataFormat,
                type: .user
            ),
            source: .ios,
            timeseries: timeseries,
            view: nil,
            version: version
        )

        return [event]
    }
}
