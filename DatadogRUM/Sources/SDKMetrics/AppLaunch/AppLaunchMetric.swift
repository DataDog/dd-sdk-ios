/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Tracks app launch telemetry and exports attributes under the "RUM App Launch" metric.
internal final class AppLaunchMetric {
    /// Definition of fields in "RUM App Launch" telemetry, following the "RUM App Launch" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        static let name = "RUM App Launch"
        /// Metric type value.
        static let typeValue = Self.name.lowercased()
        /// Namespace for bundling metric attributes.
        static let appLaunchKey = "rum_app_launch"
    }

    /// Duration of the TTID in nanoseconds.
    private var ttidDurationNs: Int64 = 0
    /// Duration of the TTFD in nanoseconds, if tracked before TTID.
    private var ttfdDurationNs: Int64?
    /// Startup type of the vitals. Can be either "cold_start" of "warm_start".
    private var startupType: String?
    /// Rule used to determine the "cold_start" type.
    private var coldStartRule: String?

    /// The reason for app startup.
    private let launchReason: LaunchReason
    /// Indicates how the process was started (e.g., user vs. background launch).
    private let taskPolicyRole: String
    /// Value if the system pre warmed the app launch.
    private let isPrewarmed: Bool

    /// Profiling status when the TTID was reported.
    private var profilingStatus: String?
    /// Profiling error when the TTID was reported.
    private var profilingError: String?

    /// App launch points of interest.
    private let launchPOIs: [String: String]

    /// Number of extra ignored TTIDs.
    private var extraTTIDsCount: Int = 0

    /// Error message when the app launch TTID is not sent.
    private let errorMessage: String?

    init(context: DatadogContext, duration: Int64, errorMessage: String? = nil) {
        self.errorMessage = errorMessage
        self.ttidDurationNs = duration

        launchReason = context.launchInfo.launchReason
        taskPolicyRole = context.launchInfo.raw.taskPolicyRole
        isPrewarmed = context.launchInfo.launchReason == .prewarming

        launchPOIs = context.launchInfo.launchPhaseDates.reduce(into: [String: String]()) { result, element in
            result[element.key.rawValue] = iso8601DateFormatter.string(from: element.value)
        }
    }

    convenience init?(vitalEvent: RUMVitalAppLaunchEvent, context: DatadogContext, coldStartRule: ColdStartRule? = nil) {
        guard vitalEvent.vital.appLaunchMetric == .ttid else {
            return nil
        }
        self.init(context: context, duration: Int64.ddWithNoOverflow(vitalEvent.vital.duration))
        self.coldStartRule = coldStartRule?.rawValue
        startupType = vitalEvent.vital.startupType?.rawValue

        if let profiling = vitalEvent.dd.profiling {
            profilingStatus = profiling.status?.rawValue
            profilingError = profiling.errorReason?.rawValue
        }
    }

    /// Increments the number of extra TTIDs collected.
    func incrementTTIDCounter() {
        extraTTIDsCount += 1
    }

    /// Tracks the duration of the TTFD vital.
    func track(ttfd: Int64) {
        ttfdDurationNs = ttfd
    }
}

// MARK: - AppLaunchMetric errors

extension AppLaunchMetric {
    static func largeTTID(context: DatadogContext, duration: TimeInterval) -> AppLaunchMetric {
        .init(context: context, duration: duration.dd.toInt64Nanoseconds, errorMessage: "The TTID collected exceeds the limit.")
    }

    static func launchNotSupported(context: DatadogContext, duration: TimeInterval) -> AppLaunchMetric {
        .init(context: context, duration: duration.dd.toInt64Nanoseconds, errorMessage: "The launch is not supported.")
    }
}

// MARK: - MetricAttributesConvertible

extension AppLaunchMetric: MetricAttributesConvertible {
    var metricName: String { Constants.name }

    func asMetricAttributes() -> [String: Encodable]? {
        [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.appLaunchKey: Attributes(
                ttidDurationNs: ttidDurationNs,
                ttfdDurationNs: ttfdDurationNs,
                startupType: startupType,
                coldStartRule: coldStartRule,
                isPrewarmed: isPrewarmed,
                launchReason: launchReason,
                taskPolicyRole: taskPolicyRole,
                profilingStatus: profilingStatus,
                profilingError: profilingError,
                extraTTIDsCount: extraTTIDsCount,
                pois: launchPOIs,
                errorMessage: errorMessage
            )
        ]
    }
}

// MARK: - Exporting Attributes

extension AppLaunchMetric {
    /// Container to encode "RUM App Launch" data according to the spec.
    internal struct Attributes: Encodable {
        let ttidDurationNs: Int64
        let ttfdDurationNs: Int64?
        let startupType: String?
        let coldStartRule: String?
        let isPrewarmed: Bool
        let launchReason: LaunchReason
        let taskPolicyRole: String
        let profilingStatus: String?
        let profilingError: String?
        let extraTTIDsCount: Int
        let pois: [String: String]
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ttidDurationNs = "ttid_duration"
            case ttfdDurationNs = "ttfd_duration"
            case startupType = "startup_type"
            case coldStartRule = "cold_start_rule"
            case isPrewarmed = "is_prewarmed"
            case launchReason = "launch_reason"
            case taskPolicyRole = "task_policy_role"
            case profilingStatus = "profiling_status"
            case profilingError = "profiling_error"
            case extraTTIDsCount = "extra_ttids_count"
            case pois = "points_of_interest"
            case errorMessage = "error_message"
        }
    }
}
