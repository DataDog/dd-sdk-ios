/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class DDSpan: OTSpan, @unchecked Sendable {
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
    private var tags: [String: OTTagValue]
    /// Span log fields.
    @ReadWriteLock
    private var logFields: [[String: Encodable & Sendable]]
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
        tags: [String: OTTagValue],
        eventBuilder: SpanEventBuilder,
        eventWriter: SpanWriteContext
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.loggingIntegration = tracer.loggingIntegration
        self.operationName = operationName
        // Assumes `tags` is already flattened and merged (see `DatadogTracer.startSpan`/`mergeTags`).
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

    func setTag(key: String, value: OTTagValue) {
        if warnIfFinished("setTag(key:value:)") {
            return
        }
        // `willSetTagWithKey` intercepts literal `SpanTags.manualKeep`/`manualDrop` + `true` (e.g. from
        // `keepTrace()`) to trigger a sampling override instead of storing a tag. Checking it once here, against
        // the caller's key/value exactly as given, before flattening, means a dictionary that happens to nest a
        // "keep"/"drop" key under a "manual" key can never be mistaken for that literal call.
        guard ddContext.span(self, willSetTagWithKey: key, value: value) else {
            return
        }
        storeFlattenedTags(flattenedTagPairs(key: key, value: value))
    }

    /// Overrides the `OTSpan` default (which loops over the public `setTag(key:value:)` per entry) so the whole
    /// dictionary is flattened and stored in one pass: `willSetTagWithKey` never sees the synthetic leaf keys
    /// this produces, and every leaf lands in `_tags` under a single lock instead of one per leaf.
    func setTag(key: String, value: [String: OTTagValue]) {
        if warnIfFinished("setTag(key:value:)") {
            return
        }
        storeFlattenedTags(flattenedTagPairs(key: key, dict: value))
    }

    private func storeFlattenedTags(_ pairs: [(String, OTTagValue)]) {
        // `setTag(key:value: OTTagValue)` calls this with exactly 1 pair whenever `value` isn't a `Dictionary` —
        // the overwhelming majority of calls — which can never collide with itself; skip the check below for it.
        if pairs.count > 1 {
            let uniqueKeyCount = Set(pairs.map { $0.0 }).count
            _ = warn(
                if: uniqueKeyCount != pairs.count,
                message: """
                Setting a dictionary tag whose keys collide once flattened (e.g. a literal "a.b" key alongside a \
                nested "a": ["b": ...] entry) is not supported; only one of the colliding tags was kept.
                """
            )
        }
        _tags.mutate { tags in
            tags.merge(pairs, uniquingKeysWith: { _, new in new })
        }
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

    func log(fields: [String: Encodable & Sendable], timestamp: Date) {
        log(message: nil, fields: fields, timestamp: timestamp)
    }

    func log(message: String?, fields: [String: Encodable & Sendable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        logFields.append(fields)
        sendSpanLogs(message: message, fields: fields, date: timestamp)
    }

    func finish(at time: Date) {
        var shouldRun = true
        _isFinished.mutate {
            if warnIfFinished("finish(at:)", isFinished: $0) {
                shouldRun = false
                return
            }
            $0 = true
        }
        if !shouldRun {
            return
        }

        if let activity = activityReference {
            ddTracer.removeSpan(span: self)
            activity.leave()
        }
        if self.ddContext.samplingDecision.samplingPriority.isKept {
            sendSpan(finishTime: time)
        }
    }

    // MARK: - Writing SpanEvent

    /// Sends span event for given `DDSpan`.
    private func sendSpan(finishTime: Date) {
        eventWriter.spanWriteContext { context, writer in
            let event = self.eventBuilder.createSpanEvent(
                context: context,
                traceID: self.ddContext.traceID,
                spanID: self.ddContext.spanID,
                parentSpanID: self.ddContext.parentSpanID,
                operationName: self.operationName,
                startTime: self.startTime,
                finishTime: finishTime,
                samplingRate: self.ddContext.sampleRate / 100.0,
                samplingPriority: self.ddContext.samplingDecision.samplingPriority,
                samplingDecisionMaker: self.ddContext.samplingDecision.decisionMaker,
                tags: self.tags,
                baggageItems: self.ddContext.baggageItems.all,
                logFields: self.logFields
            )

            let envelope = SpanEventsEnvelope(span: event, environment: context.env)
            writer.write(value: envelope)
        }
    }

    private func sendSpanLogs(message: String?, fields: [String: Encodable], date: Date) {
        loggingIntegration.writeLog(withSpanContext: ddContext, message: message, fields: fields, date: date, else: {
            DD.logger.warn("The log for span \"\(self.operationName)\" will not be send, because the Logs feature is not enabled.")
        })
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        warnIfFinished(methodName, isFinished: isFinished)
    }

    private func warnIfFinished(_ methodName: String, isFinished: Bool) -> Bool {
        return warn(
            if: isFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
