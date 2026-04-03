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
    /// Called when this span finishes (before sampling check) to feed client-side stats.
    private let onSpanFinished: ((SpanSnapshot) -> Void)?

    init(
        tracer: DatadogTracer,
        context: DDSpanContext,
        operationName: String,
        startTime: Date,
        tags: [String: Encodable],
        eventBuilder: SpanEventBuilder,
        eventWriter: SpanWriteContext,
        onSpanFinished: ((SpanSnapshot) -> Void)? = nil
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
        self.onSpanFinished = onSpanFinished
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

        if ddContext.span(self, willSetTagWithKey: key, value: value) {
            _tags.mutate { $0[key] = value }
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

    func log(fields: [String: Encodable], timestamp: Date) {
        log(message: nil, fields: fields, timestamp: timestamp)
    }

    func log(message: String?, fields: [String: Encodable], timestamp: Date) {
        if warnIfFinished("log(fields:timestamp:)") {
            return
        }
        logFields.append(fields)
        sendSpanLogs(message: message, fields: fields, date: timestamp)
    }

    func finish(at time: Date) {
        if warnIfFinished("finish(at:)") {
            return
        }
        isFinished = true

        if let activity = activityReference {
            ddTracer.removeSpan(span: self)
            activity.leave()
        }

        // Client-side stats: create snapshot BEFORE the sampling check
        // so that all spans (including sampled-out) contribute to stats.
        if let onSpanFinished = onSpanFinished {
            let snapshot = createSnapshot(finishTime: time)
            onSpanFinished(snapshot)
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

    // MARK: - Snapshot

    /// Creates a lightweight, immutable snapshot of this span for client-side stats.
    private func createSnapshot(finishTime: Date) -> SpanSnapshot {
        let currentTags = tags
        let tagsReducer = SpanTagsReducer(spanTags: currentTags, logFields: logFields)

        let resolvedService = tagsReducer.extractedServiceName
            ?? eventBuilder.service
            ?? "unnamed-service"
        let resolvedResource = tagsReducer.extractedResourceName ?? operationName
        let resolvedOperationName = tagsReducer.extractedOperationName ?? operationName

        let startNanos = startTime.timeIntervalSince1970.dd.toNanoseconds
        let durationNanos = finishTime.timeIntervalSince(startTime).dd.toNanoseconds

        let httpStatusCode: UInt32 = {
            if let code = currentTags[OTTags.httpStatusCode] as? Int {
                return UInt32(code)
            }
            return 0
        }()

        let isError = tagsReducer.extractedIsError ?? false
        let spanKind = currentTags[SpanTags.kind] as? String
            ?? currentTags[OTTags.spanKind] as? String
        let isMeasured = (currentTags["_dd.measured"] as? Int == 1)
            || (currentTags["_dd.measured"] as? Bool == true)

        var peerTags: [String: String] = [:]
        for key in StatsConcentrator.defaultPeerTagKeys {
            if let value = currentTags[key] as? String, !value.isEmpty {
                peerTags[key] = value
            }
        }

        let serviceSource = currentTags["_dd.svc_src"] as? String

        return SpanSnapshot(
            traceID: ddContext.traceID,
            spanID: ddContext.spanID,
            parentSpanID: ddContext.parentSpanID,
            service: resolvedService,
            operationName: resolvedOperationName,
            resource: resolvedResource,
            type: "custom",
            spanKind: spanKind,
            httpStatusCode: httpStatusCode,
            isError: isError,
            startTime: startNanos,
            duration: durationNanos,
            isTopLevel: ddContext.parentSpanID == nil,
            isMeasured: isMeasured,
            peerTags: peerTags,
            isSynthetics: false,
            serviceSource: serviceSource
        )
    }

    // MARK: - Private

    private func warnIfFinished(_ methodName: String) -> Bool {
        return warn(
            if: isFinished,
            message: "🔥 Calling `\(methodName)` on a finished span (\"\(operationName)\") is not allowed."
        )
    }
}
