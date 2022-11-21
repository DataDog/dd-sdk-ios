/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import class Datadog.OpenTelemetryHTTPHeadersWriter

@objc
public enum DDInjectEncoding: Int {
    case multiple = 0
    case single = 1
}

private extension OpenTelemetryHTTPHeadersWriter.InjectEncoding {
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
public class DDOpenTelemetryHTTPHeadersWriter: NSObject {
    let swiftOpenTelemetryHTTPHeadersWriter: OpenTelemetryHTTPHeadersWriter

    @objc public var tracePropagationHTTPHeaders: [String: String] {
        swiftOpenTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
    }

    @objc
    public init(
        samplingRate: Float = 20,
        injectEncoding: DDInjectEncoding = .single
    ) {
        swiftOpenTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            samplingRate: samplingRate,
            injectEncoding: .init(injectEncoding)
        )
    }
}
