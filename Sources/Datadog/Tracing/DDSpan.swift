/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
import Foundation

internal class DDSpan: OpenTracing.Span {
    private(set) var operationName: String
    private(set) var tags: [String: Codable]
    internal let startTime: Date
    internal var isFinished: Bool = false
    /// The `Tracer` which created this span.
    private let issuingTracer: DDTracer

    init(
        tracer: DDTracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Codable]
    ) {
        self.issuingTracer = tracer
        self.context = context
        self.operationName = operationName
        self.startTime = startTime
        self.tags = tags
    }

    // MARK: - Open Tracing interface

    let context: OpenTracing.SpanContext

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
        self.tags[key] = value // TODO: RUMM-340 Add thread safety when mutating `self.tags`
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
            if: isFinished, // TODO: RUMM-340 Add thread safety when reading `.isFinished`
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
