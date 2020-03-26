/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing

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
        self.operationName = operationName
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
        do {
            return try finishOrThrow(time: time)
        } catch {
            userLogger.error("🔥 Failed to finish the span: \(error)")
        }
    }

    func log(fields: [String: Codable], timestamp: Date) {
        // TODO: RUMM-292
    }

    // MARK: - Private Open Tracing helpers

    private func finishOrThrow(time: Date) throws {
        guard !isFinished else { // TODO: RUMM-340 Consider thread safety
            throw InternalError(description: "Attempted to finish already finished span: \"\(operationName)\".")
        }

        isFinished = true // TODO: RUMM-340 Consider thread safety
        issuingTracer.write(span: self, finishTime: time)
    }
}
