/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

internal class NOPOTelSpan: Span {
    var kind: OpenTelemetryApi.SpanKind = .internal

    var name: String = ""

    var context = SpanContext.create(
        traceId: TraceId.invalid,
        spanId: SpanId.invalid,
        traceFlags: TraceFlags(),
        traceState: TraceState()
    )

    var isRecording = false

    var status = Status.unset

    var description: String = "OTelNoOpSpan"

    func updateName(name: String) {}

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {}

    func addEvent(name: String) {}

    func addEvent(name: String, timestamp: Date) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {}

    func end() {
        OpenTelemetry.instance.contextProvider.removeContextForSpan(self)
    }

    func end(time: Date) {
        end()
    }

    func recordException(_ exception: any OpenTelemetryApi.SpanException, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {}

    func recordException(_ exception: any OpenTelemetryApi.SpanException, attributes: [String: OpenTelemetryApi.AttributeValue]) {}

    func recordException(_ exception: any OpenTelemetryApi.SpanException, timestamp: Date) {}

    func recordException(_ exception: any OpenTelemetryApi.SpanException) {}
}
