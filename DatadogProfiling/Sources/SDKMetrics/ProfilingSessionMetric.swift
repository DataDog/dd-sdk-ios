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
        static let noProfiledEventsErrorMessage = "Profile was not written because no profiled events were collected."
        static let profileTooLargeErrorMessage = "Profile was not written because its serialized size exceeded the limit."
        static let quotaErrorMessage = "Profile was not written because profiling quota rejected the session."
    }

    enum StartReason: String {
        case applicationLaunch = "application_launch"
        case continuous = "continuous"
        case rumOperation = "rum_operation"
    }

    /// Error codes aligned with `android.os.ProfilingResult`.
    enum ErrorCode: Int {
        /// The profiling request completed without an execution or post-processing error.
        case none = 0
        /// Profiling could not start because another profiling session was already running.
        case profilingAlreadyInProgress = 3
        /// The profiling request executed but failed to produce a profile.
        case executionFailed = 4
        /// Profiling failed for an unknown reason.
        case unknown = 8

        init(status: ProfilingContext.Status) {
            switch status {
            case .running, .stopped:
                self = .none
            case .error(reason: .alreadyStarted):
                self = .profilingAlreadyInProgress
            case .error(reason: .memoryAllocationFailed):
                self = .executionFailed
            case .unknown:
                self = .unknown
            }
        }
    }

    enum ProfileDropReason: Equatable {
        case noProfiledEvents
        case profileTooLarge
        case quotaRejected(DDProfiling.QuotaReason?)

        var errorMessage: String {
            switch self {
            case .noProfiledEvents:
                return Constants.noProfiledEventsErrorMessage
            case .profileTooLarge:
                return Constants.profileTooLargeErrorMessage
            case .quotaRejected(let reason):
                guard let reason else {
                    return Constants.quotaErrorMessage
                }
                return "\(Constants.quotaErrorMessage) Quota reason: \(reason.rawValue)."
            }
        }
    }

    var metricName: String { Constants.name }

    /// The reason why this profiling session started.
    let startReason: StartReason
    /// Status of the profiler at the end of the profiling session.
    let status: ProfilingContext.Status
    /// Duration of the profile in milliseconds.
    let durationMs: Int64?
    /// Size of the profile file in bytes.
    let fileSize: Int64?
    /// Error code describing the outcome of the profiling session.
    let errorCode: ErrorCode
    /// Error message when the profile is not sent.
    var errorMessage: String?
    /// Index of the continuous profiling cycle.
    let cycleIndex: Int?
    /// Application start info for application launch profiling.
    let appStartInfo: String?

    init(
        startReason: StartReason,
        status: ProfilingContext.Status,
        durationMs: Int64? = nil,
        fileSize: Int64? = nil,
        errorCode: ErrorCode = .none,
        errorMessage: String? = nil,
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) {
        self.startReason = startReason
        self.status = status
        self.durationMs = durationMs
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
        @unknown default:
            errorMessage = errorMessage ?? "Unknown profiling status."
        }

        return [
            SDKMetricFields.typeKey: Constants.typeValue,
            Constants.sessionKey: Attributes(
                startReason: startReason.rawValue,
                duration: durationMs,
                errorCode: errorCode.rawValue,
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
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            errorCode: .init(status: status),
            errorMessage: Constants.noProfileErrorMessage,
            cycleIndex: cycleIndex,
            appStartInfo: appStartInfo
        )
    }

    static func noData(
        startReason: StartReason,
        status: ProfilingContext.Status,
        durationMs: Int64?,
        cycleIndex: Int?,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            durationMs: durationMs,
            errorCode: .init(status: status),
            errorMessage: Constants.noDataErrorMessage,
            cycleIndex: cycleIndex,
            appStartInfo: appStartInfo
        )
    }

    static func profileDropped(
        startReason: StartReason,
        status: ProfilingContext.Status,
        reason: ProfileDropReason = .noProfiledEvents,
        cycleIndex: Int? = nil,
        appStartInfo: String? = nil
    ) -> ProfilingSessionMetric {
        .init(
            startReason: startReason,
            status: status,
            errorMessage: reason.errorMessage,
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
        /// Profile duration in milliseconds.
        let duration: Int64?
        let errorCode: Int
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
