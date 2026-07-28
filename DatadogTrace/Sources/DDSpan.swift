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
    /// Span tags, plus, for each tag `key` last set on this span via a `Dictionary` value, the leaf keys
    /// (`"key.subKey"`, ...) it flattened into — so a later `setTag` under the same `key` can drop exactly those
    /// stale leaves, instead of dropping every `"key."`-prefixed tag regardless of origin. The latter would also
    /// erase an unrelated dotted tag the caller set independently: `setTag(key: "context.foo", value: "x")`
    /// followed by `setTag(key: "context", value: "y")` must leave `"context.foo"` untouched, since it was never
    /// a leaf produced by flattening `"context"`.
    ///
    /// Both live under one lock, mutated together in `storeFlattenedTags`, so a leaf's ownership always reflects
    /// the same snapshot of `tags` it was read from — reading `flattenedChildren` and mutating `tags` under two
    /// separate locks let concurrent `setTag` calls on the same key interleave and break replace semantics.
    private struct TagsState {
        var tags: [String: OTTagValue]
        var flattenedChildren: [String: Set<String>]

        init(_ flattened: FlattenedTags) {
            self.tags = flattened.tags
            self.flattenedChildren = flattened.owners
        }
    }
    @ReadWriteLock
    private var tagsState: TagsState
    private var tags: [String: OTTagValue] {
        tagsState.tags
    }
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
        tags: FlattenedTags,
        eventBuilder: SpanEventBuilder,
        eventWriter: SpanWriteContext
    ) {
        self.ddTracer = tracer
        self.ddContext = context
        self.startTime = startTime
        self.loggingIntegration = tracer.loggingIntegration
        self.operationName = operationName
        // Assumes `tags` is already flattened and merged (see `DatadogTracer.startSpan`/`mergeTags`). Seeding
        // `flattenedChildren` from `tags.owners`, instead of starting it empty, means a later `setTag` on this
        // same key correctly clears the leaves a global dictionary tag was merged in as here, not just leaves
        // produced by a subsequent `setTag` call on the live span.
        self.tagsState = TagsState(tags)
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
        storeFlattenedTags(key: key, pairs: flattenedTagPairs(key: key, value: value))
    }

    /// Overrides the `OTSpan` default (which loops over the public `setTag(key:value:)` per entry) so the whole
    /// dictionary is flattened and stored in one pass: `willSetTagWithKey` never sees the synthetic leaf keys
    /// this produces, and every leaf lands in `_tags` under a single lock instead of one per leaf.
    func setTag(key: String, value: [String: OTTagValue]) {
        if warnIfFinished("setTag(key:value:)") {
            return
        }
        storeFlattenedTags(key: key, pairs: flattenedTagPairs(key: key, dict: value))
    }

    /// Stores `pairs` (the leaves `key`'s value flattens into), first dropping the exact `key` entry plus any
    /// leaf `flattenedChildren[key]` recorded from `key`'s previous `Dictionary` value, if any — otherwise
    /// re-setting `key` with a `Dictionary` that dropped or renamed some of its previous entries would leave
    /// those stale leaves sitting alongside the new ones, instead of `key`'s value being replaced outright as
    /// `setTag` promises. Only leaves this same method previously produced for `key` are dropped, never every
    /// tag that happens to share the `"key."` prefix — a literal dotted tag the caller set independently (e.g.
    /// `setTag(key: "context.foo", ...)`) is not a leaf of `"context"` and must survive `setTag(key: "context",
    /// ...)`.
    private func storeFlattenedTags(key: String, pairs: [(String, OTTagValue)]) {
        // `setTag(key:value: OTTagValue)` calls this with exactly 1 pair whenever `value` isn't a `Dictionary` —
        // the overwhelming majority of calls — which can never collide with itself; skip the check below for it.
        if pairs.count > 1 {
            warnIfLeafKeysCollide(
                pairs.map { $0.0 },
                message: """
                Setting a dictionary tag whose keys collide once flattened (e.g. a literal "a.b" key alongside a \
                nested "a": ["b": ...] entry) is not supported; only one of the colliding tags was kept.
                """
            )
        }
        // A dictionary flattens into pairs keyed `"key.subKey"`, never a bare `key`; a scalar (the overwhelming
        // majority of calls) flattens into exactly one pair keyed `key` itself. That's the only signal available
        // here to tell the two apart, since `flattenedTagPairs` erases whether it recursed into a `Dictionary`.
        let isContainer = pairs.count != 1 || pairs[0].0 != key
        let newLeafKeys = Set(pairs.map { $0.0 })
        _tagsState.mutate { state in
            let staleChildren = state.flattenedChildren[key] ?? []
            state.tags = state.tags.filter { $0.key != key && !staleChildren.contains($0.key) }
            state.tags.merge(pairs, uniquingKeysWith: { _, new in new })
            // E.g. if one of `key`'s own leaves is later reset independently (`setTag("ctx", ["foo": "old"])`
            // then `setTag("ctx.foo", "new")`), `flattenedChildren["ctx"]` would otherwise keep claiming
            // `"ctx.foo"` and a subsequent `setTag("ctx", "scalar")` would wrongly drop the independently-reset
            // leaf.
            releaseOwnership(of: newLeafKeys, in: &state.flattenedChildren)
            state.flattenedChildren[key] = isContainer ? newLeafKeys : nil
        }
    }

    /// Replaces this span's tags with `tags`, which are already fully flattened and merged (see `mergeTags`),
    /// without running the `willSetTagWithKey` reserved-tag hook. By this point every key is a resolved leaf
    /// that may incidentally collide with `SpanTags.manualKeep`/`manualDrop` purely as a byproduct of flattening
    /// a nested value (e.g. an OpenTelemetry attribute `["manual": ["keep": true]]`), not a caller invoking the
    /// reserved key directly — replaying such a leaf through the scalar `setTag(key:value:)` would wrongly
    /// trigger a sampling override the caller never asked for. A plain replace, same as `init`, is correct here
    /// because `OTelSpan.end()` is the only caller and it always runs before any other `setTag` call on this span.
    func setFlattenedTags(_ tags: FlattenedTags) {
        _tagsState.mutate { $0 = TagsState(tags) }
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
