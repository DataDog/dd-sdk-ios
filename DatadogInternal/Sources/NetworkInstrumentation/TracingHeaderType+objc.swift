/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The type of the tracing header injected to requests.
@objc(DDTracingHeaderType)
@objcMembers
@_spi(objc)
public final class objc_TracingHeaderType: NSObject {
    public let swiftType: TracingHeaderType

    private init(_ swiftType: TracingHeaderType) {
        self.swiftType = swiftType
    }

    /// [Datadog's `x-datadog-*` header](https://docs.datadoghq.com/real_user_monitoring/connect_rum_and_traces/?tab=browserrum#how-are-rum-resources-linked-to-traces).
    public static let datadog = objc_TracingHeaderType(.datadog)
    /// Open Telemetry B3 [Multiple headers](https://github.com/openzipkin/b3-propagation#multiple-headers).
    public static let b3multi = objc_TracingHeaderType(.b3multi)
    /// Open Telemetry B3 [Single header](https://github.com/openzipkin/b3-propagation#single-headers).
    public static let b3 = objc_TracingHeaderType(.b3)
    /// W3C [Trace Context header](https://www.w3.org/TR/trace-context/#tracestate-header)
    public static let tracecontext = objc_TracingHeaderType(.tracecontext)
}
