/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi
import DatadogInternal

extension OpenTelemetryApi.TraceId {
    /// Converts OpenTelemetry `TraceId` to Datadog `TraceID`.
    /// - Returns: Datadog `TraceID` with only higher order bits considered.
    func toDatadog() -> TraceID {
        var data = Data(count: 16)
        self.copyBytesTo(dest: &data, destOffset: 0)
        let integerLiteral = UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
        return .init(integerLiteral: integerLiteral)
    }
}
