/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Tracks app launch profiling telemetry and exports attributes under the "Profiling App Launch" metric.
internal final class AppLaunchMetric {
    /// Definition of fields in "Profiling App Launch" telemetry, following the "Profiling App Launch" telemetry spec.
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        static let name = "Profiling App Launch"
        /// Metric type value.
        static let typeValue = Self.name.lowercased()
        /// Namespace for bundling metric attributes.
        static let appLaunchKey = "profiling_app_launch"
    }

    var metricName: String { Constants.name }

    /// Status of the profiler when the TTID was received.
    let status: ProfilingContext.Status
    /// Duration of the profile in nanoseconds.
    let durationNs: Int64?
    /// Size of the profile file in bytes.
    let fileSize: Int64?
    /// Error message when the app launch profile is not sent.
    var errorMessage: String?

    init(
        status: ProfilingContext.Status,
        durationNs: Int64? = nil,
        fileSize: Int64? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.durationNs = durationNs
        self.fileSize = fileSize
        self.errorMessage = errorMessage
    }

    func asMetricAttributes() -> [String: Encodable]? {
        var stoppedReason: String?
        switch status {
        case .running:
            stoppedReason = nil
        case .stopped(reason: let reason):
            stoppedReason = reason.rawValue
        case .error(reason: let reason):
            errorMessage = reason.rawValue
        case .unknown:
            errorMessage = "Unknown profiling status."
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.appLaunchKey: Attributes(
                duration: durationNs,
                fileSize: fileSize,
                stoppedReason: stoppedReason,
                errorMessage: errorMessage
            )
        ]
    }
}

// MARK: - AppLaunchMetric errors

extension AppLaunchMetric {
    static var statusNotHandled: AppLaunchMetric { .init(status: .current, errorMessage: "Profile not handled because of the current profiler status.") }
    static var noProfile: AppLaunchMetric { .init(status: .current, errorMessage: "No profile was stored.") }
    static var noData: AppLaunchMetric { .init(status: .current, errorMessage: "Error serializing the profile.") }
}

// MARK: - Exporting Attributes

extension AppLaunchMetric {
    /// Container to encode "App Launch Profiling" data according to the spec.
    internal struct Attributes: Encodable {
        let duration: Int64?
        let fileSize: Int64?
        let stoppedReason: String?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case duration = "duration"
            case fileSize = "file_size"
            case stoppedReason = "stopped_reason"
            case errorMessage = "error_message"
        }
    }
}
