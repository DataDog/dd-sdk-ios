/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class DatadogInternal.W3CHTTPHeadersWriter

@objc
public class DDW3CHTTPHeadersWriter: NSObject {
    let swiftW3CHTTPHeadersWriter: W3CHTTPHeadersWriter

    @objc public var traceHeaderFields: [String: String] {
        swiftW3CHTTPHeadersWriter.traceHeaderFields
    }

    @objc
    public init(
        traceContextInjection: DDTraceContextInjection
    ) {
        swiftW3CHTTPHeadersWriter = W3CHTTPHeadersWriter(
            tracestate: [:],
            traceContextInjection: traceContextInjection.swiftType
        )
    }
}
