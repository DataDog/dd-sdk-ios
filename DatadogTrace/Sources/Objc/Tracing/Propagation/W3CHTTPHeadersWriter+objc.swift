/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class DatadogInternal.W3CHTTPHeadersWriter

@objc(DDW3CHTTPHeadersWriter)
@objcMembers
@_spi(objc)
public final class objc_W3CHTTPHeadersWriter: NSObject {
    let swiftW3CHTTPHeadersWriter: W3CHTTPHeadersWriter

    public var traceHeaderFields: [String: String] {
        swiftW3CHTTPHeadersWriter.traceHeaderFields
    }

    public init(
        traceContextInjection: objc_TraceContextInjection
    ) {
        swiftW3CHTTPHeadersWriter = W3CHTTPHeadersWriter(
            tracestate: [:],
            traceContextInjection: traceContextInjection.swiftType
        )
    }
}
