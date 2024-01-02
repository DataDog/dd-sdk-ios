/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

class OTelSpanBuilder: OpenTelemetryApi.SpanBuilder {
    func setParent(_ parent: OpenTelemetryApi.Span) -> Self {
        fatalError("Not implemented")
    }

    func setParent(_ parent: OpenTelemetryApi.SpanContext) -> Self {
        fatalError("Not implemented")
    }

    func setNoParent() -> Self {
        fatalError("Not implemented")
    }

    func addLink(spanContext: OpenTelemetryApi.SpanContext) -> Self {
        fatalError("Not implemented")
    }

    func addLink(spanContext: OpenTelemetryApi.SpanContext, attributes: [String : OpenTelemetryApi.AttributeValue]) -> Self {
        fatalError("Not implemented")
    }

    func setSpanKind(spanKind: OpenTelemetryApi.SpanKind) -> Self {
        fatalError("Not implemented")
    }

    func setStartTime(time: Date) -> Self {
        fatalError("Not implemented")
    }

    func setActive(_ active: Bool) -> Self {
        fatalError("Not implemented")
    }

    func startSpan() -> OpenTelemetryApi.Span {
        fatalError("Not implemented")
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        fatalError("Not implemented")
    }
}
