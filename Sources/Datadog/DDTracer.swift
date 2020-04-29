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

    // MARK: - Initialization

    // TODO: RUMM-332 Provide public API for tracer initializzation
    internal convenience init(tracingFeature: TracingFeature) {
        self.init(
            spanOutput: SpanFileOutput(
                spanBuilder: SpanBuilder(
                    appContext: tracingFeature.appContext,
                    serviceName: "ios", // TODO: RUMM-420 `serviceName` can be customized
                    userInfoProvider: tracingFeature.userInfoProvider,
                    networkConnectionInfoProvider: tracingFeature.networkConnectionInfoProvider,
                    carrierInfoProvider: tracingFeature.carrierInfoProvider
                ),
                fileWriter: tracingFeature.storage.writer
            )
        )
    }

    internal init(spanOutput: SpanOutput) {
        self.spanOutput = spanOutput
    }

    // MARK: - Open Tracing interface

    public func startSpan(operationName: String, references: [Reference]? = nil, tags: [String: Codable]? = nil, startTime: Date? = nil) -> OpenTracing.Span {
        do {
            return try startSpanOrThrow(operationName: operationName, references: references, tags: tags, startTime: startTime)
        } catch {
            consolePrint("🔥 \(error)")
            return DDNoopSpan()
        }
    }

    public func inject(spanContext: SpanContext, writer: FormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    public func extract(reader: FormatReader) -> SpanContext? {
        // TODO: RUMM-385 - we don't need to support it now
        return nil
    }

    // MARK: - Private Open Tracing helpers

    private func startSpanOrThrow(operationName: String, references: [Reference]?, tags: [String: Codable]?, startTime: Date?) throws -> OpenTracing.Span {
        guard let tracingFeature = TracingFeature.instance else {
            throw ProgrammerError(description: "`Datadog.initialize()` must be called prior to `startSpan(...)`.")
        }
        let parentSpanContext = references?.compactMap { $0.context.dd }.last
        return DDSpan(
            tracer: self,
            context: DDSpanContext(
                traceID: parentSpanContext?.traceID ?? tracingFeature.tracingUUIDGenerator.generateUnique(),
                spanID: tracingFeature.tracingUUIDGenerator.generateUnique(),
                parentSpanID: parentSpanContext?.spanID
            ),
            operationName: operationName,
            startTime: startTime ?? tracingFeature.dateProvider.currentDate(),
            tags: tags ?? [:]
        )
    }

    // MARK: - Internal

    internal func write(span: DDSpan, finishTime: Date) {
        spanOutput.write(ddspan: span, finishTime: finishTime)
    }
}
