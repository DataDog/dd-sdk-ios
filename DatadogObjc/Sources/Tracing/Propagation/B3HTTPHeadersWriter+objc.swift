/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class DatadogInternal.B3HTTPHeadersWriter

@objc
public enum DDInjectEncoding: Int {
    case multiple = 0
    case single = 1
}

private extension B3HTTPHeadersWriter.InjectEncoding {
    init(_ value: DDInjectEncoding) {
        switch value {
        case .single:
            self = .single
        case .multiple:
            self = .multiple
        }
    }
}

@objc
@available(*, deprecated, renamed: "DDB3HTTPHeadersWriter")
public final class DDOTelHTTPHeadersWriter: DDB3HTTPHeadersWriter {}

@objc
public class DDB3HTTPHeadersWriter: NSObject {
    let swiftB3HTTPHeadersWriter: B3HTTPHeadersWriter

    @objc public var traceHeaderFields: [String: String] {
        swiftB3HTTPHeadersWriter.traceHeaderFields
    }

    @objc
    public init(
        injectEncoding: DDInjectEncoding = .single,
        traceContextInjection: DDTraceContextInjection = .sampled
    ) {
        swiftB3HTTPHeadersWriter = B3HTTPHeadersWriter(
            injectEncoding: .init(injectEncoding),
            traceContextInjection: traceContextInjection.swiftType
        )
    }
}
