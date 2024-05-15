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
public class DDOTelHTTPHeadersWriter: DDB3HTTPHeadersWriter {}

@objc
public class DDB3HTTPHeadersWriter: NSObject {
    let swiftB3HTTPHeadersWriter: B3HTTPHeadersWriter

    @objc public var traceHeaderFields: [String: String] {
        swiftB3HTTPHeadersWriter.traceHeaderFields
    }

    @objc
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(
        samplingRate: Float,
        injectEncoding: DDInjectEncoding = .single
    ) {
        self.init(sampleRate: samplingRate, injectEncoding: injectEncoding)
    }

    @objc
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public init(
        sampleRate: Float = 20,
        injectEncoding: DDInjectEncoding = .single
    ) {
        swiftB3HTTPHeadersWriter = B3HTTPHeadersWriter(
            samplingStrategy: .custom(sampleRate: sampleRate),
            injectEncoding: .init(injectEncoding),
            traceContextInjection: .all
        )
    }

    @objc
    public init(
        samplingStrategy: DDTraceSamplingStrategy,
        injectEncoding: DDInjectEncoding = .single,
        traceContextInjection: DDTraceContextInjection = .all
    ) {
        swiftB3HTTPHeadersWriter = B3HTTPHeadersWriter(
            samplingStrategy: samplingStrategy.swiftType,
            injectEncoding: .init(injectEncoding),
            traceContextInjection: traceContextInjection.swiftType
        )
    }
}
