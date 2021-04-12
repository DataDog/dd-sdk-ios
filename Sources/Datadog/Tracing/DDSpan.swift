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

    func finish(at time: Date) {
        if warnIfFinished("finish(at:)") {
            return
        }
        isFinished = true
        if let activity = activityReference {
            ddTracer.activeSpansPool.removeSpan(activityReference: activity)
        }
        ddTracer.write(span: self, finishTime: time)
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
        ddTracer.writeLog(for: self, fields: fields, date: timestamp)
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: isFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
