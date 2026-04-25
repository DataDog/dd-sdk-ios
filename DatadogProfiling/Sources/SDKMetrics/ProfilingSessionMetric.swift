/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

/// Tracks profiling telemetry under the "Profiling Session" metric.
internal final class ProfilingSessionMetric {
    internal enum Constants {
        /// The name of this metric, included in telemetry log.
        static let name = "Profiling Session"
        /// Metric type value.
        static let typeValue = Self.name.lowercased()
        /// Namespace for bundling profiling session attributes.
        static let sessionKey = "profiling_session"
        static let noProfileErrorMessage = "No profile was stored."
        static let noDataErrorMessage = "Error serializing the profile."
        static let profileNotWrittenErrorMessage = "Profile was not written because no profiled events were collected."
    }

    enum StartReason: String {
        case applicationLaunch = "application_launch"
        case continuous = "continuous"
        case rumOperation = "rum_operation"
    }

    var metricName: String { Constants.name }

    /// The reason why this profiling session started.
    let startReason: StartReason
    /// Status of the profiler at the end of the profiling session.
    let status: ProfilingContext.Status
    /// Duration of the profile in nanoseconds.
    let durationNs: Int64?
    /// Size of the profile file in bytes.
    let fileSize: Int64?
    /// Error code when the profile is not sent or the profiler is in an error state.
    let errorCode: Int?
    /// Error message when the profile is not sent.
    var errorMessage: String?
    /// Index of the continuous profiling cycle.
    let cycleIndex: Int?
    /// Application start info for application launch profiling.
    let appStartInfo: String?

    init(
        startReason: StartReason,
        status: ProfilingContext.Status,
        durationNs: Int64? = nil,
        fileSize: Int64? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil,
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) {
        self.startReason = startReason
        self.status = status
        self.durationNs = durationNs
        self.fileSize = fileSize
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.cycleIndex = cycleIndex
        self.appStartInfo = appStartInfo
    }

    func asMetricAttributes() -> [String: Encodable]? {
        var stoppedReason: String?
        var errorMessage = self.errorMessage

        switch status {
        case .running:
            stoppedReason = nil
        case .stopped(reason: let reason):
            stoppedReason = reason.rawValue
        case .error(reason: let reason):
            errorMessage = errorMessage ?? reason.rawValue
        case .unknown:
            errorMessage = errorMessage ?? "Unknown profiling status."
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.sessionKey: Attributes(
                startReason: startReason.rawValue,
                duration: durationNs,
                errorCode: errorCode,
                errorMessage: errorMessage,
                fileSize: fileSize,
                stoppedReason: stoppedReason,
                cycleIndex: cycleIndex,
                appStartInfo: appStartInfo
            )
        ]
    }
}

// MARK: - ProfilingSessionMetric errors

extension ProfilingSessionMetric {
    static func noProfile(
        startReason: StartReason,
        status: ProfilingContext.Status,
        errorCode: Int?,
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            errorCode: errorCode,
            errorMessage: Constants.noProfileErrorMessage,
            cycleIndex: cycleIndex,
            appStartInfo: appStartInfo
        )
    }

    static func noData(
        startReason: StartReason,
        status: ProfilingContext.Status,
        durationNs: Int64?,
        errorCode: Int?,
        cycleIndex: Int?,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            durationNs: durationNs,
            errorCode: errorCode,
            errorMessage: Constants.noDataErrorMessage,
            cycleIndex: cycleIndex,
            appStartInfo: appStartInfo
        )
    }

    static func profileNotWritten(
        startReason: StartReason,
        status: ProfilingContext.Status,
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            errorMessage: Constants.profileNotWrittenErrorMessage,
            cycleIndex: cycleIndex,
            appStartInfo: appStartInfo
        )
    }
}

// MARK: - Exporting Attributes

extension ProfilingSessionMetric {
    /// Container to encode Profiling Session data according to the spec.
    internal struct Attributes: Encodable {
        let startReason: String
        let duration: Int64?
        let errorCode: Int?
        let errorMessage: String?
        let fileSize: Int64?
        let stoppedReason: String?
        let cycleIndex: Int?
        let appStartInfo: String?

        enum CodingKeys: String, CodingKey {
            case startReason = "start_reason"
            case duration = "duration"
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case fileSize = "file_size"
            case stoppedReason = "stopped_reason"
            case cycleIndex = "cycle_index"
            case appStartInfo = "app_start_info"
        }
    }
}

#endif
