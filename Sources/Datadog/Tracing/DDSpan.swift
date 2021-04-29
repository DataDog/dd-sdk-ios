/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if SPM_BUILD
import _Datadog_Private
#endif

internal class DDSpan: OTSpan {
    /// The `Tracer` which created this span.
    private let ddTracer: Tracer
    /// Span context.
    internal let ddContext: DDSpanContext
    /// Span creation date
    internal let startTime: Date
    /// Builds the `Span` from user input.
    internal let spanBuilder: SpanEventBuilder
    /// Writes the `Span` to file.
    private let spanOutput: SpanOutput
    /// Writes span logs to output. `nil` if Logging feature is disabled.
    private let logOutput: LoggingForTracingAdapter.AdaptedLogOutput?

    /// Unsynchronized span operation name. Use `self.operationName` setter & getter.
    private var unsafeOperationName: String
    private(set) var operationName: String {
        get { ddTracer.queue.sync { unsafeOperationName } }
        set { ddTracer.queue.async { self.unsafeOperationName = newValue } }
    }

    /// Unsynchronized span tags. Use `self.tags` setter & getter.
    private var unsafeTags: [String: Encodable]
    var tags: [String: Encodable] {
        ddTracer.queue.sync { unsafeTags }
    }

    /// Unsychronized span log fields. Use `self.logFields` setter & getter.
    private var unsafeLogFields: [[String: Encodable]]
    /// A collection of all log fields send for this span.
    var logFields: [[String: Encodable]] {
        ddTracer.queue.sync { unsafeLogFields }
    }

    /// Unsychronized span completion. Use `self.isFinished` setter & getter.
    private var unsafeIsFinished: Bool
    private(set) var isFinished: Bool {
        get { ddTracer.queue.sync { unsafeIsFinished } }
        set { ddTracer.queue.async { self.unsafeIsFinished = newValue } }
    }

    private var activityReference: ActivityReference?

    init(
        tracer: Tracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Encodable],
        logFields: [[String: Encodable]] = []
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.spanBuilder = tracer.spanBuilder
        self.spanOutput = tracer.spanOutput
        self.logOutput = tracer.logOutput
        self.unsafeOperationName = operationName
        self.unsafeTags = tags
        self.unsafeIsFinished = false
        self.unsafeLogFields = logFields
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
        ddTracer.queue.async {
            self.unsafeTags[key] = value
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
            ddTracer.activeSpansPool.addSpan(span: self, activityReference: activityReference)
        }
        return self
    }

    func log(fields: [String: Encodable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        ddTracer.queue.async {
            self.unsafeLogFields.append(fields)
        }
        sendSpanLogs(fields: fields, date: timestamp)
    }

    func finish(at time: Date) {
        if warnIfFinished("finish(at:)") {
            return
        }
        isFinished = true
        if let activity = activityReference {
            ddTracer.activeSpansPool.removeSpan(activityReference: activity)
        }
        sendSpan(finishTime: time)
    }

    // MARK: - Writting SpanEvent

    /// Sends span event for given `DDSpan`.
    private func sendSpan(finishTime: Date) {
        // Baggage items must be read before entering the `tracer.queue` as it uses that queue for internal sync.
        let baggageItems = ddContext.baggageItems.all

        // This queue adds performance optimisation by reading all `unsafe*` values in one block and performing
        // the `builder.createSpan()` off the main thread. This is important as the span creation includes
        // attributes encoding to JSON string values (for tags and extra user info). It captures `self` strongly
        // as it is very likely to be deallocated after return.
        ddTracer.queue.async {
            let span = self.spanBuilder.createSpanEvent(
                traceID: self.ddContext.traceID,
                spanID: self.ddContext.spanID,
                parentSpanID: self.ddContext.parentSpanID,
                operationName: self.unsafeOperationName,
                startTime: self.startTime,
                finishTime: finishTime,
                tags: self.unsafeTags,
                baggageItems: baggageItems,
                logFields: self.unsafeLogFields
            )
            self.spanOutput.write(span: span)
        }
    }

    private func sendSpanLogs(fields: [String: Encodable], date: Date) {
        guard let logOutput = logOutput else {
            userLogger.warn("The log for span \"\(operationName)\" will not be send, because the Logging feature is disabled.")
            return
        }
        logOutput.writeLog(withSpanContext: ddContext, fields: fields, date: date)
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: isFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
