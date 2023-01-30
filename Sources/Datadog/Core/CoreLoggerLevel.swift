/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension CoreLoggerLevel {
    /// For compatibility with V1's `Datadog.verbosityLevel`.
    var toV1LogLevel: LogLevel {
        switch self {
        case .debug:    return .debug
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }
}

extension LogLevel {
    var toCoreLogLevel: CoreLoggerLevel {
        switch self {
        case .info, .debug, .notice: return .debug
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        }
    }
}
