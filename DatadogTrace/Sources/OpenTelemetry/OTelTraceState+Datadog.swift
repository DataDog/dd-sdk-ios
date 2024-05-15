/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

extension OpenTelemetryApi.TraceState {
    /// Returns the tracestate as a string as defined in the W3C standard.
    /// https://www.w3.org/TR/trace-context/#tracestate-header-field-values
    /// Example: rojo=00f067aa0ba902b7,congo=t61rcWkgMzE
    /// - Returns: tracestate as a string
    public func w3c() -> String {
        return self.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}
