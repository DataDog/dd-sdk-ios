/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Tracks the state of RUM view and exports attributes for "RUM View Ended" telemetry.
///
/// It is a reference type and contains mutable state, but thread safety is assured by only accessing it from `RUMViewScope`.
internal final class ViewEndedMetric {
    /// Definition of fields in "RUM View Ended" telemetry, following the "RUM View Ended" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
        static let name = "RUM View Ended"
        /// Metric type value.
        static let typeValue = "rum view ended"
        /// Namespace for bundling metric attributes ("rve" = "RUM View Ended").
        static let rveKey = "rve"
    }

    internal enum MetricPredicateType: String {
        case timeBasedDefault = "time_based_default"
        case timeBasedCustom = "time_based_custom"
        case custom = "custom"
    }

    /// The view URL as reported in RUM data.
    var viewURL: String?
    /// The type of instrumentation that started this view.
    /// It can be `nil` if view was started implicitly by RUM, which is the case for "ApplicationLaunch" and "Background" views.
    var instrumentationType: SessionEndedMetric.ViewInstrumentationType?
    /// Duration of the view in nanoseconds (equal to `@view.time_spent`).
    var durationNs: Int64?

    /// The value of `@view.loading_time`.
    var loadingTime: Int64?

    /// The value or "no value reason" for `@view.network_settled_time` (Time-to-Network-Settled, TNS).
    var tnsResult: Result<TimeInterval, TNSNoValueReason>?
    /// The type of `NetworkSettledResourcePredicate` used for TNS tracking.
    let tnsConfigPredicate: MetricPredicateType

    /// The value or "no value reason" for `@view.interaction_to_next_view_time` (Interaction-to-Next-View, INV).
    var invResult: Result<TimeInterval, INVNoValueReason>?
    /// The type of `NextViewActionPredicate` used for TNS tracking.
    let invConfigPredicate: MetricPredicateType

    init(
        tnsConfigPredicate: MetricPredicateType,
        invConfigPredicate: MetricPredicateType
    ) {
        self.tnsConfigPredicate = tnsConfigPredicate
        self.invConfigPredicate = invConfigPredicate
    }

    // MARK: - Exporting Attributes

    /// A container for encoding "RUM View Ended" according to the spec.
    internal struct Attributes: Encodable {
        struct MetricValue: Encodable {
            /// Metric value in nanoseconds.
            var value: Int64?
            /// Reason for missing value.
            var noValueReason: String?
            /// Strategy for computing value in this metric.
            var config: String?

            enum CodingKeys: String, CodingKey {
                case value = "value"
                case noValueReason = "no_value_reason"
                case config = "config"
            }
        }

        enum ViewType: String, Encodable {
            case applicationLaunch = "application_launch"
            case background = "background"
            case custom = "custom"
        }

        /// Duration of the view in nanoseconds (equal to `view.time_spent`).
        var duration: Int64
        /// Tracks `@view.loading_time` metric.
        var loadingTime: MetricValue?
        /// Tracks `@view.network_settled_time` metric.
        var tns: MetricValue?
        /// Tracks `@view.interaction_to_next_view_time` metric.
        var inv: MetricValue?
        /// The type of the view.
        var viewType: ViewType?
        /// The type of instrumentation that this view was started by.
        var instrumentationType: SessionEndedMetric.ViewInstrumentationType?

        enum CodingKeys: String, CodingKey {
            case duration = "duration"
            case loadingTime = "loading_time"
            case tns = "tns"
            case inv = "inv"
            case viewType = "view_type"
            case instrumentationType = "instrumentation_type"
        }
    }

    func asMetricAttributes() -> [String: Encodable]? {
        guard let durationNs else {
            return nil
        }

        let loadingTime = loadingTime.map { Attributes.MetricValue(value: $0) }
        var tns = Attributes.MetricValue(config: tnsConfigPredicate.rawValue)
        var inv = Attributes.MetricValue(config: invConfigPredicate.rawValue)

        switch tnsResult {
        case .success(let value): tns.value = value.toInt64Nanoseconds
        case .failure(let noValueReason): tns.noValueReason = noValueReason.rawValue
        default: break
        }

        switch invResult {
        case .success(let value): inv.value = value.toInt64Nanoseconds
        case .failure(let noValueReason): inv.noValueReason = noValueReason.rawValue
        default: break
        }

        var viewType: Attributes.ViewType?
        switch viewURL {
        case RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL: viewType = .applicationLaunch
        case RUMOffViewEventsHandlingRule.Constants.backgroundViewURL: viewType = .background
        case .some: viewType = .custom
        default: break
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.rveKey: Attributes(
                duration: durationNs,
                loadingTime: loadingTime,
                tns: tns,
                inv: inv,
                viewType: viewType,
                instrumentationType: instrumentationType
            )
        ]
    }
}

internal extension NetworkSettledResourcePredicate {
    var metricPredicateType: ViewEndedMetric.MetricPredicateType {
        switch self {
        case let timeBased as TimeBasedTNSResourcePredicate:
            return timeBased.threshold == TimeBasedTNSResourcePredicate.defaultThreshold ? .timeBasedDefault : .timeBasedCustom
        default:
            return .custom
        }
    }
}

internal extension NextViewActionPredicate {
    var metricPredicateType: ViewEndedMetric.MetricPredicateType {
        switch self {
        case let timeBased as TimeBasedINVActionPredicate:
            return timeBased.maxTimeToNextView == TimeBasedINVActionPredicate.defaultMaxTimeToNextView ? .timeBasedDefault : .timeBasedCustom
        default:
            return .custom
        }
    }
}
