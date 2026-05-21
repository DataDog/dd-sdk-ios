/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class ProfilingTelemetryController {
    /// The default sample rate for "Profiling Session" metric (20%),
    /// applied in addition to the Profiling continuous sample rate (5% by default).
    static let defaultSampleRate: SampleRate = 20
    /// Telemetry endpoint for sending metrics.
    let telemetry: Telemetry
    /// The sample rate for "Profiling Session" metric.
    let sampleRate: SampleRate
    /// Metric with Profiling configurations.
    let configMetric: ConfigurationMetric
    /// App launch data attached to application launch profiling sessions.
    @ReadWriteLock
    private var appStartInfo: String?
    /// Index of the current continuous profiling cycle.
    @ReadWriteLock
    private var continuousCycleIndex = 0

    init(
        sampleRate: SampleRate = ProfilingTelemetryController.defaultSampleRate,
        telemetry: Telemetry = NOPTelemetry(),
        configMetric: ConfigurationMetric = ConfigurationMetric()
    ) {
        self.sampleRate = sampleRate
        self.telemetry = telemetry
        self.configMetric = configMetric
    }

    /// Registers app launch data that will be attached to application launch profiling sessions.
    func register(context: DatadogContext) {
        appStartInfo = context.launchInfo.profilingAppStartInfo
    }

    /// Sends a metric for a written profile, decorated with shared profiling telemetry state.
    func sendProfile(durationNs: Int64, fileSize: Int64, for operation: ProfilingOperation) {
        send(
            .init(
                startReason: operation.startReason,
                status: .current,
                durationNs: durationNs,
                fileSize: fileSize,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    /// Sends a metric for a profile that could not be serialized.
    func sendNoData(durationNs: Int64?, for operation: ProfilingOperation) {
        send(
            .noData(
                startReason: operation.startReason,
                status: .current,
                durationNs: durationNs,
                errorCode: Int(dd_profiler_get_status().rawValue),
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    /// Sends a metric when no profile was captured.
    func sendNoProfile(for operation: ProfilingOperation) {
        send(
            .noProfile(
                startReason: operation.startReason,
                status: .current,
                errorCode: Int(dd_profiler_get_status().rawValue),
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    /// Sends a metric for a profile that was captured but intentionally not written.
    func sendProfileNotWritten(for operation: ProfilingOperation) {
        send(
            .profileNotWritten(
                startReason: operation.startReason,
                status: .current,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    func send(_ metric: ProfilingSessionMetric) {
        guard var metricAttributes = metric.asMetricAttributes() else {
            telemetry.debug("Failed to compute attributes for '\(metric.metricName)'")
            return
        }
        metricAttributes.merge(AggregationDiagnosticsMetric.consumeDiagnostics().asMetricAttributes() ?? [:]) { $1 }
        metricAttributes.merge(configMetric.asMetricAttributes() ?? [:]) { $1 }

        telemetry.metric(name: metric.metricName, attributes: metricAttributes, sampleRate: sampleRate)
    }

    private func cycleIndex(for operation: ProfilingOperation) -> Int? {
        guard operation == .continuousProfiling else {
            return nil
        }

        var cycleIndex = 0
        _continuousCycleIndex.mutate {
            cycleIndex = $0
            $0 += 1
        }
        return cycleIndex
    }
}

private extension ProfilingOperation {
    var startReason: ProfilingSessionMetric.StartReason {
        switch self {
        case .appLaunch:
            .applicationLaunch
        case .continuousProfiling:
            .continuous
        case .customProfiling:
            .rumOperation
        }
    }
}

private extension LaunchInfo {
    var profilingAppStartInfo: String {
        switch launchReason {
        case .userLaunch:
            "user_launch"
        case .backgroundLaunch:
            "background_launch"
        case .prewarming:
            "prewarming"
        case .uncertain:
            "uncertain"
        }
    }
}

#endif
