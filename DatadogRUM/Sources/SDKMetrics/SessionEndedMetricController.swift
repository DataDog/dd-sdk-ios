/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A controller responsible for managing "RUM Session Ended" metrics.
internal final class SessionEndedMetricController {
    /// Dictionary to keep track of pending metrics, keyed by session ID.
    @ReadWriteLock
    private var pendingMetrics: [String: SessionEndedMetric] = [:]

    /// Telemetry endpoint for sending metrics.
    private let telemetry: Telemetry

    /// Initializes a new instance of the metric controller.
    /// - Parameter telemetry: The telemetry endpoint used for sending metrics.
    init(telemetry: Telemetry) {
        self.telemetry = telemetry
    }

    /// Starts a new metric for a given session.
    /// - Parameters:
    ///   - sessionID: The ID of the session to track.
    ///   - precondition: The precondition that led to starting this session.
    ///   - context: The SDK context at the moment of starting this session.
    /// - Returns: The newly created `SessionEndedMetric` instance.
    func startMetric(sessionID: String, precondition: RUMSessionPrecondition?, context: DatadogContext) -> SessionEndedMetric {
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: precondition, context: context)
        pendingMetrics[sessionID] = metric
        return metric
    }

    /// Retrieves the metric for a given session ID.
    /// - Parameter sessionID: The ID of the session to retrieve the metric for.
    /// - Returns: The `SessionEndedMetric` instance if found, otherwise `nil`.
    func metric(for sessionID: String) -> SessionEndedMetric? {
        return pendingMetrics[sessionID]
    }

    /// Ends the metric for a given session, sending it to telemetry and removing it from pending metrics.
    /// - Parameter sessionID: The ID of the session to end the metric for.
    func endMetric(sessionID: String) {
        guard let metric = pendingMetrics[sessionID] else {
            return
        }
        telemetry.metric(name: SessionEndedMetric.Constants.name, attributes: metric.asMetricAttributes())
        pendingMetrics[sessionID] = nil
    }
}
