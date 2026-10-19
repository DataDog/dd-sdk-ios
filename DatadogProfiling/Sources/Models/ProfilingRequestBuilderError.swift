/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Reported errors while building a request for the profiling intake.
internal enum ProfilingRequestBuilderError: Error, Equatable {
    /// The batch does not hold exactly one event, which is all the intake accepts per request.
    case unexpectedEventCount(count: Int)
    /// The profile event was read without the attachments it is uploaded with.
    case missingAttachments
}

extension ProfilingRequestBuilderError: TelemetrySanitizableError {
    func sanitize() -> TelemetrySanitizedError {
        TelemetrySanitizedError(unsafelyDescribing: self)
    }
}

extension ProfilingRequestBuilderError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unexpectedEventCount(let count):
            return "Profiling batch holds \(count) events, expected exactly 1"
        case .missingAttachments:
            return "Profiling event is missing its attachments metadata"
        }
    }
}
