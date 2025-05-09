/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class DatadogInternal.HTTPHeadersWriter

@objc(DDHTTPHeadersWriter)
@objcMembers
@_spi(objc)
public final class objc_HTTPHeadersWriter: NSObject {
    let swiftHTTPHeadersWriter: HTTPHeadersWriter

    public var traceHeaderFields: [String: String] {
        swiftHTTPHeadersWriter.traceHeaderFields
    }

    public init(traceContextInjection: objc_TraceContextInjection) {
        swiftHTTPHeadersWriter = HTTPHeadersWriter(traceContextInjection: traceContextInjection.swiftType)
    }
}
