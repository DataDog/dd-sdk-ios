/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
import Foundation

internal class DDSpan: Span {
    private(set) var operationName: String
    /// The `Tracer` which created this span.
    internal let issuingTracer: DDTracer
    internal let startTime: Date
    internal var isFinished: Bool = false

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
        if warnIfFinished("setOperationName(_:)") {
            return
        }
        self.operationName = operationName
    }

    func setTag(key: String, value: Codable) {
        if warnIfFinished("setTag(key:value:)") {
            return
        }
        // TODO: RUMM-292
    }

    func setBaggageItem(key: String, value: String) {
        if warnIfFinished("setBaggageItem(key:value:)") {
            return
        }
        // TODO: RUMM-292
    }

    func baggageItem(withKey key: String) -> String? {
        if warnIfFinished("baggageItem(withKey:)") {
            return nil
        }
        // TODO: RUMM-292
        return nil
    }

    func finish(at time: Date) {
        if warnIfFinished("finish(at:)") {
            return
        }
        isFinished = true // TODO: RUMM-340 Consider thread safety
        issuingTracer.write(span: self, finishTime: time)
    }

    func log(fields: [String: Codable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        // TODO: RUMM-292
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: isFinished, // TODO: RUMM-340 Consider thread safety when reading `.isFinished`
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
