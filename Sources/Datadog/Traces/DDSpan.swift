/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing

internal class DDSpan: Span {
    /// The `Tracer` which created this span.
    let issuingTracer: DDTracer
    let operationName: String
    let startTime: Date

    init(tracer: DDTracer, operationName: String, parentSpanContext: DDSpanContext?, startTime: Date) {
        self.issuingTracer = tracer
        self.operationName = operationName
        self.startTime = startTime
        self.context = DDSpanContext(
            traceID: parentSpanContext?.traceID ?? .generateUnique(),
            spanID: .generateUnique()
        )
    }

    // MARK: - Open Tracing interface

    let context: SpanContext

    func tracer() -> Tracer {
        return issuingTracer
    }

    func setOperationName(_ operationName: String) {
        // TODO: RUMM-293
    }

    func setTag(key: String, value: Codable) {
        // TODO: RUMM-292
    }

    func setBaggageItem(key: String, value: String) {
        // TODO: RUMM-292
    }

    func baggageItem(withKey key: String) -> String? {
        // TODO: RUMM-292
        return nil
    }

    func finish(at time: Date) {
        // TODO: RUMM-293
    }

    func log(fields: [String: Codable], timestamp: Date) {
        // TODO: RUMM-292
    }
}
