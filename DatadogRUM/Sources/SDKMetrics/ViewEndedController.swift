/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Interface for Telemetry metrics.
internal protocol MetricAttributesConvertible {
    /// Indicates the metric being tracked.
    var metricName: String { get }
    /// Transforms the telemetry data in an encodable dictionary.
    func asMetricAttributes() -> [String: Encodable]?
}

internal final class ViewEndedController {
    /// The default sample rate for "view ended" metrics (0.75%), applied in addition to the telemetry sample rate (20% by default).
    static let defaultSampleRate: SampleRate = 0.75

    /// Telemetry endpoint for sending metrics.
    private let telemetry: Telemetry
    /// The sample rate for the "View Ended" metrics.
    internal var sampleRate: SampleRate
    /// Telemetry metrics for the current view.
    private var metrics: [String: MetricAttributesConvertible] = [:]

    init(
        telemetry: Telemetry,
        sampleRate: SampleRate = ViewEndedController.defaultSampleRate
    ) {
        self.telemetry = telemetry
        self.sampleRate = sampleRate
    }

    /// Adds a metric to be tracked by telemetry.
    func add(metric: MetricAttributesConvertible) {
        metrics[metric.metricName] = metric
    }

    /// Sends the metrics telemetry.
    ///
    /// - Note: This method is expected to be called exactly once per view to report metrics associated with the view's lifecycle.
    func send() {
        metrics.keys.forEach { key in
            if let attributes = metrics[key]?.asMetricAttributes() {
                telemetry.metric(name: key, attributes: attributes, sampleRate: sampleRate)
            } else {
                telemetry.debug("Failed to compute attributes for '\(key)'")
            }
        }
        metrics.removeAll()
    }
}

// MARK: - ViewEndedMetric

extension ViewEndedController {
    /// Tracks the view update event.
    /// - Parameters:
    ///   - view: the view update event to track
    ///   - instrumentationType: the type of instrumentation used to start this view (only the first value for each `view.id` is tracked; succeeding values
    ///   will be ignored so it is okay to pass value on first call and then follow with `nil` for next updates of given `view.id`)
    func track(
        viewEvent: RUMViewEvent,
        instrumentationType: InstrumentationType?
    ) {
        guard let metric = self.metrics[ViewEndedMetric.Constants.name] as? ViewEndedMetric else {
            return
        }

        metric.instrumentationType = instrumentationType ?? metric.instrumentationType
        metric.viewURL = viewEvent.view.url
        metric.durationNs = viewEvent.view.timeSpent
        metric.loadingTime = viewEvent.view.loadingTime
    }

    /// Tracks the value computed for the Time-to-Network-Settled (TNS) metric.
    func track(networkSettledResult: Result<TimeInterval, TNSNoValueReason>) {
        guard let metric = self.metrics[ViewEndedMetric.Constants.name] as? ViewEndedMetric else {
            return
        }

        metric.tnsResult = networkSettledResult
    }

    /// Tracks the value computed for the Interaction-to-Next-View (INV) metric.
    func track(interactionToNextViewResult: Result<TimeInterval, INVNoValueReason>) {
        guard let metric = self.metrics[ViewEndedMetric.Constants.name] as? ViewEndedMetric else {
            return
        }

        metric.invResult = interactionToNextViewResult
    }
}

// MARK: - ViewHitchesMetric

extension ViewEndedController {
    /// Tracks the telemetry for view hitches.
    /// - Parameters:
    ///   - hitchesTelemetry: the view hitches telemetry to track.
    ///   - viewDuration: the total duration of the view.
    func track(hitchesTelemetry: HitchesTelemetryModel, viewDuration: Int64? = nil) {
        guard let metric = self.metrics[ViewHitchesMetric.Constants.name] as? ViewHitchesMetric else {
            return
        }

        metric.count = hitchesTelemetry.hitchesCount
        metric.ignoredCount = hitchesTelemetry.ignoredHitchesCount
        metric.ignoredDurationNs = hitchesTelemetry.ignoredDurationNs
        metric.viewDurationNs = viewDuration
        metric.dynamicFramingApplied = hitchesTelemetry.didApplyDynamicFraming
    }
}
