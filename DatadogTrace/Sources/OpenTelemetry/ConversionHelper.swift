/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

struct ConversionHelper {
    static func ToUInt64(from spanId: SpanId) -> UInt64 {
        var data = Data(count: 8)
        spanId.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    static func ToUInt64(from traceId: TraceId) -> UInt64 {
        var data = Data(count: 16)
        traceId.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }
}

extension SpanId {
    func toLong() -> UInt64 {
        var data = Data(count: 8)
        self.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    func toDatadogSpanID() -> DatadogInternal.SpanID {
        .init(integerLiteral: toLong())
    }
}


extension TraceId {
    func toLong() -> UInt64 {
        var data = Data(count: 16)
        self.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    func toDatadogTraceID() -> DatadogInternal.TraceID {
        .init(integerLiteral: toLong())
    }
}
