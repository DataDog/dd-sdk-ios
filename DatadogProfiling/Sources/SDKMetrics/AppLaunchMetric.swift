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

    var errorMessage: String = ""
    let status: ProfilingContext.Status
    /// Duration of the profile in nanoseconds.
    let durationNs: Int64?
    /// Size of the profile file in bytes.
    let fileSize: Int64?

    init(
        status: ProfilingContext.Status,
        errorMessage: String = "",
        durationNs: Int64? = nil,
        fileSize: Int64? = nil
    ) {
        self.status = status
        self.errorMessage = errorMessage
        self.durationNs = durationNs
        self.fileSize = fileSize
    }
}

extension AppLaunchMetric {
    static var statusNotHandled: AppLaunchMetric { .init(status: .current, errorMessage: "Profile not handled because of the current status.") }
    static var noProfile: AppLaunchMetric { .init(status: .current, errorMessage: "No profile.") }
    static var noData: AppLaunchMetric { .init(status: .current, errorMessage: "Error serializing profile.") }
}

// MARK: - MetricAttributesConvertible

extension AppLaunchMetric: MetricAttributesConvertible {
    var metricName: String { Constants.name }

    func asMetricAttributes() -> [String: Encodable]? {
        var stoppedReason = ""
        switch status {
        case .running:
            errorMessage += "Profiling continues to run."
        case .stopped(reason: let reason):
            stoppedReason = reason.rawValue
        case .error(reason: let reason):
            errorMessage += reason.rawValue
        case .unknown:
            errorMessage += "Unknown profiling status."
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.appLaunchKey: Attributes(
                duration: durationNs ?? 0,
                fileSize: fileSize,
                stoppedReason: stoppedReason,
                errorMessage: errorMessage
            )
        ]
    }
}

// MARK: - Exporting Attributes

extension AppLaunchMetric {
    /// Container to encode "App Launch Profiling" data according to the spec.
    internal struct Attributes: Encodable {
        let duration: Int64
        let fileSize: Int64?
        let stoppedReason: String
        let errorMessage: String

        enum CodingKeys: String, CodingKey {
            case duration = "duration"
            case fileSize = "file_size"
            case stoppedReason = "stopped_reason"
            case errorMessage = "error_message"
        }
    }
}

extension AppLaunchMetric.Attributes {
    internal struct Configuration: Encodable {
        /// Sampling rate in Hz.
        let samplingRate: Int
        /// Max number of samples of the profile.
        let bufferSize: Int
        /// Max number of frames per trace.
        let stackDepth: Int
        /// Threads covered in the process.
        let threadCoverage: Int
        /// Sample rate for profiling from 0% to 100%.
        let profilingSampleRate: Int

        enum CodingKeys: String, CodingKey {
            case samplingRate = "samplingRate"
            case bufferSize = "bufferSize"
            case stackDepth = "stackDepth"
            case threadCoverage = "threadCoverage"
            case profilingSampleRate = "profilingSampleRate"
        }
    }
}
