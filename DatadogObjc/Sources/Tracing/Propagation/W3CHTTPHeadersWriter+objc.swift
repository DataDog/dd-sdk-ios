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
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate)
    }

    @objc
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public init(sampleRate: Float = 20) {
        swiftW3CHTTPHeadersWriter = W3CHTTPHeadersWriter(
            samplingStrategy: .custom(sampleRate: sampleRate),
            tracestate: [:]
        )
    }

    @objc
    public init(
        samplingStrategy: DDTraceSamplingStrategy
    ) {
        swiftW3CHTTPHeadersWriter = W3CHTTPHeadersWriter(
            samplingStrategy: samplingStrategy.swiftType,
            tracestate: [:]
        )
    }
}
