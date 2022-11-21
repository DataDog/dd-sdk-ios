/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import class Datadog.OpenTelemetryHTTPHeadersWriter

@objc
public class DDOpenTelemetryHTTPHeadersWriter: NSObject {
    let swiftOpenTelemetryHTTPHeadersWriter: OpenTelemetryHTTPHeadersWriter

    @objc public var tracePropagationHTTPHeaders: [String: String] {
        swiftOpenTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
    }

    @objc
    public init(
        samplingRate: Float = 20,
        openTelemetryHeaderType: OpenTelemetryHTTPHeadersWriter.OpenTelemetryHeaderType = .single
    ) {
        swiftOpenTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            samplingRate: samplingRate,
            openTelemetryHeaderType: openTelemetryHeaderType
        )
    }
}
