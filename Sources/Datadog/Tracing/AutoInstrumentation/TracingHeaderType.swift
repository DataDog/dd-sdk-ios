/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The type of the tracing header injected to requests.
///
/// - `dd` - [Datadog's `x-datadog-*` header](https://docs.datadoghq.com/real_user_monitoring/connect_rum_and_traces/?tab=browserrum#how-are-rum-resources-linked-to-traces).
/// - `b3s` - Open Telemetry B3 [Single header](https://github.com/openzipkin/b3-propagation#single-headers).
/// - `b3m` - Open Telemetry B3 [Multiple headers](https://github.com/openzipkin/b3-propagation#multiple-headers).
/// - `w3c` - W3C [Trace Context header](https://www.w3.org/TR/trace-context/#tracestate-header)
public enum TracingHeaderType: Hashable {
    case dd
    case b3s
    case b3m
    case w3c
}

public typealias FirstPartyHosts = [String: Set<TracingHeaderType>]

extension FirstPartyHosts {
    var hosts: Set<String> {
        return Set(keys)
    }
}
