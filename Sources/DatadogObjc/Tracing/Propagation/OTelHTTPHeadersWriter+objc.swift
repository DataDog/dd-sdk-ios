/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import class Datadog.OTelHTTPHeadersWriter

@objc
public enum DDInjectEncoding: Int {
    case multiple = 0
    case single = 1
}

private extension OTelHTTPHeadersWriter.InjectEncoding {
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
public class DDOTelHTTPHeadersWriter: NSObject {
    let swiftOTelHTTPHeadersWriter: OTelHTTPHeadersWriter

    @objc public var tracePropagationHTTPHeaders: [String: String] {
        swiftOTelHTTPHeadersWriter.tracePropagationHTTPHeaders
    }

    @objc
    public init(
        samplingRate: Float = 20,
        injectEncoding: DDInjectEncoding = .single
    ) {
        swiftOTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            samplingRate: samplingRate,
            injectEncoding: .init(injectEncoding)
        )
    }
}
