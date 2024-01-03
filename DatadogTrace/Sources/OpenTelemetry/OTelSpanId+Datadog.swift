/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi
import DatadogInternal

extension OpenTelemetryApi.SpanId {
    /// Converts OpenTelemetry `SpanId` to Datadog `SpanID`.
    /// - Returns: Datadog `SpanID`.
    func toDatadog() -> SpanID {
        var data = Data(count: 8)
        self.copyBytesTo(dest: &data, destOffset: 0)
        let integerLiteral = UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
        return .init(integerLiteral: integerLiteral)
    }
}
