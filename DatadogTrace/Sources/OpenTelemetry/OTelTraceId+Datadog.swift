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
        return .init(idHi: self.idHi, idLo: self.idLo)
    }
}
