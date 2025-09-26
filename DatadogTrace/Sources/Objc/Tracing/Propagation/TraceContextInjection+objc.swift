/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines whether the trace context should be injected into all requests or only sampled ones.
@objc(DDTraceContextInjection)
@_spi(objc)
public enum objc_TraceContextInjection: Int {
    internal var swiftType: DatadogInternal.TraceContextInjection {
        switch self {
        case .all:
            return .all
        case .sampled:
            return .sampled
        }
    }

    /// Injects trace context into all requests irrespective of the sampling decision.
    case all

    /// Injects trace context only into sampled requests.
    case sampled
}
