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
    private var metricsBySessionID: [RUMUUID: SessionEndedMetric] = [:]
    /// Array to keep track of pending session IDs in their start order.
    @ReadWriteLock
    private var pendingSessionIDs: [RUMUUID] = []

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
    func startMetric(sessionID: RUMUUID, precondition: RUMSessionPrecondition?, context: DatadogContext) {
        guard sessionID != RUMUUID.nullUUID else {
            return // do not track metric when session is not sampled
        }
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: precondition, context: context)
        metricsBySessionID[sessionID] = metric
        pendingSessionIDs.append(sessionID)
    }

    /// Tracks the view event that occurred during the session.
    /// - Parameters:
    ///   - view: the view event to track
    ///   - sessionID: session ID to track this view in (pass `nil` to track it for the last started session)
    func track(view: RUMViewEvent, in sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.track(view: view) }
    }

    /// Tracks the kind of SDK error that occurred during the session.
    /// - Parameters:
    ///   - sdkErrorKind: the kind of SDK error to track
    ///   - sessionID: session ID to track this error in (pass `nil` to track it for the last started session)
    func track(sdkErrorKind: String, in sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.track(sdkErrorKind: sdkErrorKind) }
    }

    /// Signals that the session was stopped with `stopSession()` API.
    /// - Parameter sessionID: session ID to mark as stopped (pass `nil` to track it for the last started session)
    func trackWasStopped(sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.trackWasStopped() }
    }

    /// Ends the metric for a given session, sending it to telemetry and removing it from pending metrics.
    /// - Parameter sessionID: The ID of the session to end the metric for.
    func endMetric(sessionID: RUMUUID) {
        guard let metric = metricsBySessionID[sessionID] else {
            return
        }
        telemetry.metric(name: SessionEndedMetric.Constants.name, attributes: metric.asMetricAttributes())
        metricsBySessionID[sessionID] = nil
        pendingSessionIDs.removeAll(where: { $0 == sessionID }) // O(n), but "ending the metric" is very rare event
    }

    private func updateMetric(for sessionID: RUMUUID?, _ mutation: (inout SessionEndedMetric?) -> Void) {
        guard let sessionID = (sessionID ?? pendingSessionIDs.last) else {
            return
        }
        _metricsBySessionID.mutate { metrics in  mutation(&metrics[sessionID]) }
    }
}
