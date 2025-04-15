/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Tracks View Hitches telemetry and exports attributes under the "RUM UI Slowness" metric.
internal final class ViewHitchesMetric {
    /// Definition of fields in "RUM UI Slowness" telemetry, following the "RUM UI Slowness" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
        static let name = "RUM UI Slowness"
        /// Metric type value.
        static let typeValue = Self.name.lowercased()
        /// Namespace for bundling metric attributes.
        static let uiSlownessKey = "rum_ui_slowness"
    }

    /// Total amount of slow frames collected within the view scope.
    var count: Int = 0
    /// Amount of slow frames that were outside of the lower and upper thresholds.
    var ignoredCount: Int = 0
    /// Value indicating the extra duration used to calculate the slow frame rate.
    var ignoredDurationNs: Int64 = 0
    /// Duration of the view in nanoseconds (equal to `@view.time_spent`).
    var viewDurationNs: Int64?
    /// Value indicating that the view experienced a change on the frames per second.
    var dynamicFramingApplied: Bool = false
    /// The configuration used to collect View Hitches.
    let config: ViewHitchesMetric.Attributes.Configuration

    init(
        maxCount: Int,
        slowFrameThreshold: Int64,
        maxDuration: Int64,
        viewMinDuration: Int64
    ) {
        self.config = .init(
            maxCount: maxCount,
            slowFrameThreshold: slowFrameThreshold,
            maxDuration: maxDuration,
            viewMinDuration: viewMinDuration
        )
    }
}

// MARK: - MetricAttributesConvertible

extension ViewHitchesMetric: MetricAttributesConvertible {
    var metricName: String { Constants.name }

    func asMetricAttributes() -> [String: Encodable]? {
        guard let viewDurationNs else {
            return nil
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.uiSlownessKey: Attributes(
                viewDuration: viewDurationNs,
                slowFrames: .init(
                    count: count,
                    ignoredCount: ignoredCount,
                    ignoredDuration: ignoredDurationNs,
                    dynamicFramingApplied: dynamicFramingApplied,
                    config: config
                )
            )
        ]
    }
}

// MARK: - Exporting Attributes

extension ViewHitchesMetric {
    /// Container to encode "SlowFrames" data according to the spec.
    internal struct Attributes: Encodable {
        /// Duration of the view in nanoseconds (equal to `@view.time_spent`).
        let viewDuration: Int64
        /// Telemetry data for slow frames.
        let slowFrames: SlowFrames

        enum CodingKeys: String, CodingKey {
            case viewDuration = "view_duration"
            case slowFrames = "slow_frames"
        }
    }
}

extension ViewHitchesMetric.Attributes {
    internal struct SlowFrames: Encodable {
        /// Total amount of slow frames collected within the view scope.
        let count: Int
        /// Amount of slow frames that were outside of the lower and upper thresholds.
        let ignoredCount: Int
        /// Value indicating the extra duration used to calculate the slow frame rate.
        let ignoredDuration: Int64
        /// Value indicating that the view experienced a change on the frames per second.
        let dynamicFramingApplied: Bool
        /// The configuration used to collect View Hitches.
        let config: Configuration

        enum CodingKeys: String, CodingKey {
            case count
            case ignoredCount = "ignored_count"
            case ignoredDuration = "ignored_duration"
            case dynamicFramingApplied = "dynamic_framing_applied"
            case config
        }
    }
}

extension ViewHitchesMetric.Attributes {
    internal struct Configuration: Encodable {
        /// Maximum number of slow frames that can be reached.
        let maxCount: Int
        /// Minimum delay to consider the slow frames.
        let slowFrameThreshold: Int64
        /// Boundary between slow frames from frozen frames in nanoseconds.
        let maxDuration: Int64
        /// Baseline View duration to track hitches in nanoseconds.
        let viewMinDuration: Int64

        enum CodingKeys: String, CodingKey {
            case maxCount = "max_count"
            case slowFrameThreshold = "slow_frame_threshold"
            case maxDuration = "max_duration"
            case viewMinDuration = "view_min_duration"
        }
    }
}
