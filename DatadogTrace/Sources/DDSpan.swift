/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class DDSpan: OTSpan {
    /// The `Tracer` which created this span.
    private let ddTracer: DatadogTracer
    /// Span context.
    internal let ddContext: DDSpanContext
    /// Span creation date
    internal let startTime: Date
    /// Writes span logs to Logging Feature. `nil` if Logging feature is disabled.
    private let loggingIntegration: TracingWithLoggingIntegration

    /// Span operation name.
    @ReadWriteLock
    private var operationName: String
    /// Span tags.
    @ReadWriteLock
    private var tags: [String: Encodable]
    /// Span log fields.
    @ReadWriteLock
    private var logFields: [[String: Encodable]]
    /// If this span has completed.
    @ReadWriteLock
    private var isFinished: Bool
    @ReadWriteLock
    private var activityReference: ActivityReference?
    /// Builds span events.
    private let eventBuilder: SpanEventBuilder
    /// Writes span events to core.
    private let eventWriter: SpanWriteContext

    init(
        tracer: DatadogTracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Encodable],
        eventBuilder: SpanEventBuilder,
        eventWriter: SpanWriteContext
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.loggingIntegration = tracer.loggingIntegration
        self.operationName = operationName
        self.tags = tags
        self.logFields = []
        self.isFinished = false
        self.eventBuilder = eventBuilder
        self.eventWriter = eventWriter
    }

    // MARK: - Open Tracing interface

    var context: OTSpanContext {
        return ddContext
    }

    func tracer() -> OTTracer {
        return ddTracer
    }

    func setOperationName(_ operationName: String) {
        if warnIfFinished("setOperationName(_:)") {
            return
        }
        self.operationName = operationName
    }

    func setTag(key: String, value: Encodable) {
        if warnIfFinished("setTag(key:value:)") {
            return
        }
        _tags.mutate { $0[key] = value }
    }

    func setBaggageItem(key: String, value: String) {
        if warnIfFinished("setBaggageItem(key:value:)") {
            return
        }
        ddContext.baggageItems.set(key: key, value: value)
    }

    func baggageItem(withKey key: String) -> String? {
        if warnIfFinished("baggageItem(withKey:)") {
            return nil
        }
        return ddContext.baggageItems.get(key: key)
    }

    @discardableResult
    func setActive() -> OTSpan {
        activityReference = ActivityReference()
        if let activityReference = activityReference {
            ddTracer.addSpan(span: self, activityReference: activityReference)
        }
        return self
    }

    func log(fields: [String: Encodable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        logFields.append(fields)
        sendSpanLogs(fields: fields, date: timestamp)
    }

    func finish(at time: Date) {
        if warnIfFinished("finish(at:)") {
            return
        }
        isFinished = true

        if let activity = activityReference {
            ddTracer.removeSpan(activityReference: activity)
        }
        sendSpan(finishTime: time, sampler: ddTracer.localTraceSampler)
    }

    // MARK: - Writing SpanEvent

    /// Sends span event for given `DDSpan`.
    private func sendSpan(finishTime: Date, sampler: Sampler) {
        eventWriter.spanWriteContext { context, writer in
            let event = self.eventBuilder.createSpanEvent(
                context: context,
                traceID: self.ddContext.traceID,
                spanID: self.ddContext.spanID,
                parentSpanID: self.ddContext.parentSpanID,
                operationName: self.operationName,
                startTime: self.startTime,
                finishTime: finishTime,
                samplingRate: sampler.samplingRate / 100.0,
                isKept: sampler.sample(),
                tags: self.tags,
                baggageItems: self.ddContext.baggageItems.all,
                logFields: self.logFields
            )

            let envelope = SpanEventsEnvelope(span: event, environment: context.env)
            writer.write(value: envelope)
        }
    }

    private func sendSpanLogs(fields: [String: Encodable], date: Date) {
        loggingIntegration.writeLog(withSpanContext: ddContext, fields: fields, date: date, else: {
            DD.logger.warn("The log for span \"\(self.operationName)\" will not be send, because the Logs feature is not enabled.")
        })
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: isFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
