/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class DatadogInternal.HTTPHeadersWriter

@objc
public class DDHTTPHeadersWriter: NSObject {
    let swiftHTTPHeadersWriter: HTTPHeadersWriter

    @objc public var traceHeaderFields: [String: String] {
        swiftHTTPHeadersWriter.traceHeaderFields
    }

    @objc
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate)
    }

    @objc
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public init(sampleRate: Float = 20) {
        swiftHTTPHeadersWriter = HTTPHeadersWriter(
            samplingStrategy: .custom(sampleRate: sampleRate),
            traceContextInjection: .sampled
        )
    }

    @objc
    public init(
        samplingStrategy: DDTraceSamplingStrategy,
        traceContextInjection: DDTraceContextInjection
    ) {
        swiftHTTPHeadersWriter = HTTPHeadersWriter(
            samplingStrategy: samplingStrategy.swiftType,
            traceContextInjection: traceContextInjection.swiftType
        )
    }
}
