/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
import Foundation

public class DDTracer: Tracer {
    /// Writes `Span` objects to output.
    private let spanOutput: SpanOutput

    // TODO: RUMM-332 Consider builder pattern to initialize the tracer
    internal init(spanOutput: SpanOutput) {
        self.spanOutput = spanOutput
    }

    // MARK: - Open Tracing interface

    public func startSpan(operationName: String, references: [Reference]? = nil, tags: [String: Codable]? = nil, startTime: Date? = nil) -> Span {
        do {
            return try startSpanOrThrow(operationName: operationName, references: references, tags: tags, startTime: startTime)
        } catch {
            consolePrint("🔥 \(error)")
            return DDNoopSpan()
        }
    }

    public func inject(spanContext: SpanContext, writer: FormatWriter) {
        // TODO: RUMM-292
    }

    public func extract(reader: FormatReader) -> SpanContext? {
        // TODO: RUMM-292
        return nil
    }

    // MARK: - Private Open Tracing helpers

    private func startSpanOrThrow(operationName: String, references: [Reference]?, tags: [String: Codable]?, startTime: Date?) throws -> Span {
        guard let datadog = Datadog.instance else {
            throw ProgrammerError(description: "`Datadog.initialize()` must be called prior to `startSpan(...)`.")
        }

        let parentSpanContext = references?.compactMap { $0.context as? DDSpanContext }.last
        return DDSpan(
            tracer: self,
            operationName: operationName,
            parentSpanContext: parentSpanContext,
            startTime: startTime ?? datadog.dateProvider.currentDate()
        )
    }

    // MARK: - Internal

    func write(span: DDSpan, finishTime: Date) {
        spanOutput.write(span: span, finishTime: finishTime)
    }
}
