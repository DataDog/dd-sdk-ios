/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

internal final class ProfilingTelemetryController {
    /// The default sample rate for "Profiling Session" metrics (20%),
    /// applied in addition to the global telemetry sample rate.
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

    /// Best-effort sequence of continuous reports in the current RUM session.
    @ReadWriteLock
    private var continuousSession: (id: String?, nextCycleIndex: Int) = (nil, 0)

    init(
        sampleRate: SampleRate = ProfilingTelemetryController.defaultSampleRate,
        telemetry: Telemetry = NOPTelemetry(),
        configMetric: ConfigurationMetric = ConfigurationMetric()
    ) {
        self.sampleRate = sampleRate
        self.telemetry = telemetry
        self.configMetric = configMetric
    }

    /// Updates telemetry context and resets continuous numbering for a new RUM session.
    func register(context: DatadogContext) {
        appStartInfo = context.launchInfo.profilingAppStartInfo
        if let sessionID = context.additionalContext(ofType: RUMCoreContext.self)?.sessionID {
            _continuousSession.mutate { session in
                if session.id != sessionID {
                    session = (sessionID, 0)
                }
            }
        }
    }

    /// Sends a metric for a terminal allocation failure.
    func sendAllocationFailure(for operation: ProfilingOperation) {
        send(
            .allocationFailure(
                startReason: operation.startReason,
                status: .current,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    /// Sends a metric for a written profile, decorated with shared profiling telemetry state.
    /// Heap-only writes must not consume the pending CPU aggregation diagnostics.
    func sendProfile(
        durationMs: Int64,
        fileSize: Int64,
        for operation: ProfilingOperation,
        profileTypes: [ProfilingSessionMetric.ProfileType] = [.cpu],
        memoryDiagnostics: MemoryDiagnostics? = nil
    ) {
        send(
            .init(
                startReason: operation.startReason,
                status: profileTypes.contains(.cpu) ? .current : .running,
                durationMs: durationMs,
                fileSize: fileSize,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            ),
            profileTypes: profileTypes,
            memoryDiagnostics: memoryDiagnostics
        )
    }

    /// Sends a metric for a profile that could not be serialized.
    func sendNoData(
        durationMs: Int64?,
        for operation: ProfilingOperation,
        profileTypes: [ProfilingSessionMetric.ProfileType] = [.cpu],
        memoryDiagnostics: MemoryDiagnostics? = nil
    ) {
        send(
            .noData(
                startReason: operation.startReason,
                status: profileTypes.contains(.cpu) ? .current : .running,
                durationMs: durationMs,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            ),
            profileTypes: profileTypes,
            memoryDiagnostics: memoryDiagnostics
        )
    }

    /// Sends a metric when no profile was captured.
    func sendNoProfile(for operation: ProfilingOperation) {
        let status = ProfilingContext.Status.current
        guard status != .error(reason: .memoryAllocationFailed) else {
            return
        }

        send(
            .noProfile(
                startReason: operation.startReason,
                status: status,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            )
        )
    }

    /// Sends a metric for a profile that was intentionally dropped.
    /// Heap-only drops must not consume the pending CPU aggregation diagnostics.
    func sendProfileDropped(
        for operation: ProfilingOperation,
        reason: ProfilingSessionMetric.ProfileDropReason = .noProfiledEvents,
        profileTypes: [ProfilingSessionMetric.ProfileType] = [.cpu],
        memoryDiagnostics: MemoryDiagnostics? = nil
    ) {
        send(
            .profileDropped(
                startReason: operation.startReason,
                status: profileTypes.contains(.cpu) ? .current : .running,
                reason: reason,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            ),
            profileTypes: profileTypes,
            memoryDiagnostics: memoryDiagnostics
        )
    }

    func send(
        _ metric: ProfilingSessionMetric,
        profileTypes: [ProfilingSessionMetric.ProfileType] = [.cpu],
        memoryDiagnostics: MemoryDiagnostics? = nil
    ) {
        guard var metricAttributes = metric.asMetricAttributes(profileTypes: profileTypes) else {
            telemetry.debug("Failed to compute attributes for '\(metric.metricName)'")
            return
        }
        let cpu = profileTypes.contains(.cpu) ? ProfilingDiagnostics.CPUDiagnostics.consume() : nil
        if cpu != nil || memoryDiagnostics != nil {
            metricAttributes[ProfilingDiagnostics.Constants.diagnosticsKey] = ProfilingDiagnostics(
                cpu: cpu,
                memory: memoryDiagnostics
            )
        }
        if profileTypes.contains(.cpu) {
            metricAttributes.merge(configMetric.asMetricAttributes() ?? [:]) { $1 }
        }

        telemetry.metric(name: metric.metricName, attributes: metricAttributes, sampleRate: sampleRate)
    }

    /// Reports an unsuccessful memory cycle without consulting CPU state or consuming CPU diagnostics.
    func sendMemoryDiagnostics(
        _ diagnostics: MemoryDiagnostics,
        for operation: ProfilingOperation
    ) {
        let failed: Bool
        switch diagnostics.captureResult {
        case .startFailed, .captureFailed, .serializationFailed, .invalidTime:
            failed = true
        default:
            failed = false
        }
        send(
            .init(
                startReason: operation.startReason,
                status: .running,
                errorCode: failed ? .executionFailed : .none,
                errorMessage: failed ? "Memory profile: \(diagnostics.captureResult.rawValue)." : nil,
                cycleIndex: cycleIndex(for: operation),
                appStartInfo: operation == .appLaunch ? appStartInfo : nil
            ),
            profileTypes: [.memory],
            memoryDiagnostics: diagnostics
        )
    }

    private func cycleIndex(for operation: ProfilingOperation) -> Int? {
        guard operation == .continuousProfiling else {
            return nil
        }
        var index = 0
        _continuousSession.mutate { session in
            index = session.nextCycleIndex
            session.nextCycleIndex += 1
        }
        return index
    }
}

private extension ProfilingOperation {
    var startReason: ProfilingSessionMetric.StartReason {
        switch self {
        case .appLaunch:
            .applicationLaunch
        case .continuousProfiling:
            .continuous
        case .trigger:
            .trigger
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
        @unknown default:
            "uncertain"
        }
    }
}

#endif
