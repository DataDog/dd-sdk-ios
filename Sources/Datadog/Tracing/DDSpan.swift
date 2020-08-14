/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import os.activity
import _Datadog_Private

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
    private(set) var tags: [String: Encodable] {
        get { ddTracer.queue.sync { unsafeTags } }
        set { ddTracer.queue.async { self.unsafeTags = newValue } }
    }

    /// Unsychronized span completion. Use `self.isFinished` setter & getter.
    private var unsafeIsFinished: Bool
    private(set) var isFinished: Bool {
        get { ddTracer.queue.sync { unsafeIsFinished } }
        set { ddTracer.queue.async { self.unsafeIsFinished = newValue } }
    }

    /// Unsychronized span log fields. Use `self.logFields` setter & getter.
    private var unsafeLogFields: [[String: Encodable]] = []
    /// A collection of all log fields send for this span.
    private(set) var logFields: [[String: Encodable]] {
        get { ddTracer.queue.sync { unsafeLogFields } }
        set { ddTracer.queue.async { self.unsafeLogFields = newValue } }
    }

    private var activityId: os_activity_id_t?
    private var activityState = os_activity_scope_state_s()

    init(
        tracer: Tracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Encodable]
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.unsafeOperationName = operationName
        self.unsafeTags = tags
        self.unsafeIsFinished = false
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
        self.tags[key] = value
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
        os_activity_scope_leave(&activityState)
        if let activityId = activityId {
            ddTracer.activeSpansPool.removeSpan(activityId: activityId)
        }
        ddTracer.write(span: self, finishTime: time)
    }

    @discardableResult
    func setActive() -> OTSpan {
        let dso = UnsafeMutableRawPointer(mutating: #dsohandle)
        let activity = _os_activity_create(dso, "InitDDSpanContext", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT)
        activityId = os_activity_get_identifier(activity, nil)
        os_activity_scope_enter(activity, &activityState)
        if let activityId = activityId {
            ddTracer.activeSpansPool.addSpan(span: self, activityId: activityId)
        }
        return self
    }

    func log(fields: [String: Encodable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        logFields.append(fields)
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
