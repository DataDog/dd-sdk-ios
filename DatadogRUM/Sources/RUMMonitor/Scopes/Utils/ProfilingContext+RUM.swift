/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

extension ProfilingContext {
    /// The profiling info reported as additional context of RUM events.
    var ddProfiling: DDProfiling {
        .init(
            errorReason: errorReason,
            quotaReason: quotaReason,
            status: profilingStatus
        )
    }

    /// The profiler status reported to the RUM data model.
    ///
    /// Returns:
    /// - `.running` when the profiler is actively running.
    /// - `.stopped` when the profiler has stopped for any reason.
    /// - `.error` when the profiler encountered an error or its status could not be determined.
    private var profilingStatus: DDProfiling.Status {
        switch status {
        case .running:
            return .running
        case .stopped:
            return .stopped
        case .error:
            return .error
        case .unknown:
            return .error
        }
    }

    /// The reason the Profiler encountered an error. This attribute is only present if the status is `error`.
    ///
    /// Possible values:
    /// - `unexpected-exception`: An exception occurred when starting the Profiler.
    private var errorReason: DDProfiling.ErrorReason? {
        // RUM-15325: Update RUM schema with the mobile profiler errors.
        guard case .error(reason: let reason) = status else {
            return nil
        }

        switch reason {
        case .memoryAllocationFailed:
            return .unexpectedException
        case .alreadyStarted:
            return nil
        }
    }
}
