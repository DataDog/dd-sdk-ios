/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A controller responsible for managing "RUM Session Ended" metrics.
internal final class SessionEndedMetricController {
    /// The default sample rate for "session ended" metric (15%), applied in addition to the telemetry sample rate (20% by default).
    static let defaultSampleRate: SampleRate = 15

    /// Dictionary to keep track of pending metrics, keyed by session ID.
    @ReadWriteLock
    private var metricsBySessionID: [RUMUUID: SessionEndedMetric] = [:]
    /// Array to keep track of pending session IDs in their start order.
    private var pendingSessionIDs: [RUMUUID] = []

    /// Telemetry endpoint for sending metrics.
    private let telemetry: Telemetry

    /// The sample rate for "RUM Session Ended" metric.
    internal var sampleRate: SampleRate

    /// Initializes a new instance of the metric controller.
    /// - Parameters:
    ///    - telemetry: The telemetry endpoint used for sending metrics.
    ///    - sampleRate: The sample rate for "RUM Session Ended" metric.

    init(telemetry: Telemetry, sampleRate: SampleRate) {
        self.telemetry = telemetry
        self.sampleRate = sampleRate
    }

    /// Starts a new metric for a given session.
    /// - Parameters:
    ///   - sessionID: The ID of the session to track.
    ///   - precondition: The precondition that led to starting this session.
    ///   - context: The SDK context at the moment of starting this session.
    ///   - tracksBackgroundEvents: If background events tracking is enabled for this session.
    /// - Returns: The newly created `SessionEndedMetric` instance.
    func startMetric(sessionID: RUMUUID, precondition: RUMSessionPrecondition?, context: DatadogContext, tracksBackgroundEvents: Bool) {
        guard sessionID != RUMUUID.nullUUID else {
            return // do not track metric when session is not sampled
        }
        _metricsBySessionID.mutate { metrics in
            metrics[sessionID] = SessionEndedMetric(sessionID: sessionID, precondition: precondition, context: context, tracksBackgroundEvents: tracksBackgroundEvents)
            pendingSessionIDs.append(sessionID)
        }
    }

    /// Tracks the view event that occurred during the session.
    /// - Parameters:
    ///   - view: the view event to track
    ///   - instrumentationType: the type of instrumentation used to start this view (only the first value for each `view.id` is tracked; succeeding values
    ///   will be ignored so it is okay to pass value on first call and then follow with `nil` for next updates of given `view.id`)
    ///   - sessionID: session ID to track this view in (pass `nil` to track it for the last started session)
    func track(
        view: RUMViewEvent,
        instrumentationType: InstrumentationType?,
        in sessionID: RUMUUID?
    ) {
        updateMetric(for: sessionID) { try $0?.track(view: view, instrumentationType: instrumentationType) }
    }

    /// Tracks the action event that occurred during the session.
    /// - Parameters:
    ///   - action: the action event to track
    ///   - instrumentationType: the type of instrumentation used to start this action
    ///   - sessionID: session ID to track this action in (pass `nil` to track it for the last started session)
    func track(
        action: RUMActionEvent,
        instrumentationType: InstrumentationType,
        in sessionID: RUMUUID?
    ) {
        updateMetric(for: sessionID) { $0?.track(action: action, instrumentationType: instrumentationType) }
    }

    /// Tracks the kind of SDK error that occurred during the session.
    /// - Parameters:
    ///   - sdkErrorKind: the kind of SDK error to track
    ///   - sessionID: session ID to track this error in (pass `nil` to track it for the last started session)
    func track(sdkErrorKind: String, in sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.track(sdkErrorKind: sdkErrorKind) }
    }

    /// Tracks an event missed due to absence of an active view.
    /// - Parameters:
    ///   - missedEventType: the type of an event that was missed
    ///   - sessionID: session ID to track this error in (pass `nil` to track it for the last started session)
    func track(missedEventType: SessionEndedMetric.MissedEventType, in sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.track(missedEventType: missedEventType) }
    }

    /// Signals that the session was stopped with `stopSession()` API.
    /// - Parameter sessionID: session ID to mark as stopped (pass `nil` to track it for the last started session)
    func trackWasStopped(sessionID: RUMUUID?) {
        updateMetric(for: sessionID) { $0?.trackWasStopped() }
    }

    /// Ends the metric for a given session, sending it to telemetry and removing it from pending metrics.
    /// - Parameter sessionID: The ID of the session to end the metric for.
    func endMetric(sessionID: RUMUUID, with context: DatadogContext) {
        _metricsBySessionID.mutate { metrics in
            guard let metric = metrics[sessionID] else {
                return
            }
            telemetry.metric(
                name: SessionEndedMetric.Constants.name,
                attributes: metric.asMetricAttributes(with: context),
                sampleRate: sampleRate
            )
            metrics[sessionID] = nil
            pendingSessionIDs.removeAll(where: { $0 == sessionID }) // O(n), but "ending the metric" is very rare event
        }
    }

    private func updateMetric(for sessionID: RUMUUID?, _ mutation: (inout SessionEndedMetric?) throws -> Void) {
        _metricsBySessionID.mutate { metrics in
            guard let sessionID = (sessionID ?? pendingSessionIDs.last) else {
                return
            }
            do {
                try mutation(&metrics[sessionID])
            } catch let error {
                telemetry.error(error)
            }
        }
    }
}
