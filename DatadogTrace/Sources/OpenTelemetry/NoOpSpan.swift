/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

class NoOpSpan: Span {
    var kind: OpenTelemetryApi.SpanKind = .internal

    var name: String = ""

    var context: SpanContext = SpanContext.create(traceId: TraceId.invalid,
                                                  spanId: SpanId.invalid,
                                                  traceFlags: TraceFlags(),
                                                  traceState: TraceState())

    var isRecording: Bool = false

    var status: Status = Status.ok

    var description: String = "NoOpSpan"

    func updateName(name: String) {}

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {}

    func addEvent(name: String) {}

    func addEvent(name: String, timestamp: Date) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {}

    func end() {}

    func end(time: Date) {}
}
