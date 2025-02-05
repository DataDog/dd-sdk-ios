/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class ViewEndedMetricController {
    /// The default sample rate for "view ended" metric (0.75%), applied in addition to the telemetry sample rate (20% by default).
    static let defaultSampleRate: SampleRate = 0.75

    /// Telemetry endpoint for sending metrics.
    private let telemetry: Telemetry
    /// The sample rate for "RUM View Ended" metric.
    internal var sampleRate: SampleRate
    /// Metric data for current view.
    private var metric: ViewEndedMetric
    /// If the metric was sent to telemetry.
    private var wasSent = false

    init(
        tnsPredicateType: ViewEndedMetric.MetricPredicateType,
        invPredicateType: ViewEndedMetric.MetricPredicateType,
        telemetry: Telemetry,
        sampleRate: SampleRate = ViewEndedMetricController.defaultSampleRate
    ) {
        self.telemetry = telemetry
        self.sampleRate = sampleRate
        self.metric = ViewEndedMetric(tnsConfigPredicate: tnsPredicateType, invConfigPredicate: invPredicateType)
    }

    /// Tracks the view update event.
    /// - Parameters:
    ///   - view: the view update event to track
    ///   - instrumentationType: the type of instrumentation used to start this view (only the first value for each `view.id` is tracked; succeeding values
    ///   will be ignored so it is okay to pass value on first call and then follow with `nil` for next updates of given `view.id`)
    func track(
        viewEvent: RUMViewEvent,
        instrumentationType: SessionEndedMetric.ViewInstrumentationType?
    ) {
        metric.instrumentationType = instrumentationType ?? metric.instrumentationType
        metric.viewURL = viewEvent.view.url
        metric.durationNs = viewEvent.view.timeSpent
        metric.loadingTime = viewEvent.view.loadingTime
    }

    /// Tracks the value computed for the Time-to-Network-Settled (TNS) metric.
    func track(networkSettledResult: Result<TimeInterval, TNSNoValueReason>) {
        metric.tnsResult = networkSettledResult
    }

    /// Tracks the value computed for the Interaction-to-Next-View (INV) metric.
    func track(interactionToNextViewResult: Result<TimeInterval, INVNoValueReason>) {
        metric.invResult = interactionToNextViewResult
    }

    /// Sends the "view ended" metric telemetry.
    ///
    /// - Note: This method is expected to be called exactly once per view to report metrics associated with the view's lifecycle.
    func send() {
        guard !wasSent else { // sanity check
            telemetry.debug("Trying to send 'view ended' more than once")
            return
        }
        guard let attributes = metric.asMetricAttributes() else {
            telemetry.debug("Failed to compute attributes fo 'view ended'")
            return
        }

        telemetry.metric(name: ViewEndedMetric.Constants.name, attributes: attributes, sampleRate: sampleRate)
        wasSent = true
    }
}
