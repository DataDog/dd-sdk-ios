/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

internal class DatadogTracer: OTTracer, OpenTelemetryApi.Tracer  {
    internal weak var core: DatadogCoreProtocol?

    /// Global tags configured for Trace feature.
    let tags: [String: Encodable]
    let service: String?
    let networkInfoEnabled: Bool
    let spanEventMapper: ((SpanEvent) -> SpanEvent)?
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    let queue: DispatchQueue
    /// Integration with Core Context.
    let contextReceiver: ContextMessageReceiver
    /// Integration with Logging.
    let loggingIntegration: TracingWithLoggingIntegration

    let tracingUUIDGenerator: TraceIDGenerator

    /// Date provider for traces.
    let dateProvider: DateProvider

    let activeSpansPool = ActiveSpansPool()

    let sampler: Sampler

    /// Telemetry interface.
    let telemetry: Telemetry

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        sampler: Sampler,
        tags: [String: Encodable],
        service: String?,
        networkInfoEnabled: Bool,
        spanEventMapper: ((SpanEvent) -> SpanEvent)?,
        tracingUUIDGenerator: TraceIDGenerator,
        dateProvider: DateProvider,
        contextReceiver: ContextMessageReceiver,
        loggingIntegration: TracingWithLoggingIntegration,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.core = core
        self.tags = tags
        self.service = service
        self.networkInfoEnabled = networkInfoEnabled
        self.spanEventMapper = spanEventMapper
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )

        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.dateProvider = dateProvider
        self.contextReceiver = contextReceiver
        self.loggingIntegration = loggingIntegration
        self.sampler = sampler
        self.telemetry = telemetry
    }

    // MARK: - Open Tracing interface

    func startSpan(operationName: String, references: [OTReference]? = nil, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        let parentSpanContext = references?.compactMap { $0.context.dd }.last ?? activeSpan?.context as? DDSpanContext
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: parentSpanContext),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    func startRootSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: nil),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    func inject(spanContext: OTSpanContext, writer: OTFormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    func extract(reader: OTFormatReader) -> OTSpanContext? {
        // TODO: RUMM-385 - make `HTTPHeadersReader` available in public API
        reader.extract()
    }

    var activeSpan: OTSpan? {
        return activeSpansPool.getActiveSpan()
    }

    // MARK: - Internal

    internal func createSpanContext(parentSpanContext: DDSpanContext? = nil) -> DDSpanContext {
        return DDSpanContext(
            traceID: parentSpanContext?.traceID ?? tracingUUIDGenerator.generate(),
            spanID: tracingUUIDGenerator.generate(),
            parentSpanID: parentSpanContext?.spanID,
            baggageItems: BaggageItems(parent: parentSpanContext?.baggageItems)
        )
    }

    internal func startSpan(spanContext: DDSpanContext, operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        var combinedTags = self.tags
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        if let rumTags = contextReceiver.context.rum {
            combinedTags.merge(rumTags) { $1 }
        }

        let span = DDSpan(
            tracer: self,
            context: spanContext,
            operationName: operationName,
            startTime: startTime ?? dateProvider.now,
            tags: combinedTags,
            telemetry: telemetry
        )
        return span
    }

    internal func addSpan(span: DDSpan, activityReference: ActivityReference) {
        activeSpansPool.addSpan(span: span, activityReference: activityReference)
        updateCoreAttributes()
    }

    internal func removeSpan(activityReference: ActivityReference) {
        activeSpansPool.removeSpan(activityReference: activityReference)
        updateCoreAttributes()
    }

    private func updateCoreAttributes() {
        let context = activeSpan?.context as? DDSpanContext

        core?.set(
            baggage: context.map {
                SpanCoreContext(
                    traceID: String($0.traceID),
                    spanID: String($0.spanID)
                )
            },
            forKey: SpanCoreContext.key
        )
    }

    func spanBuilder(spanName: String) -> OpenTelemetryApi.SpanBuilder {
        WrapperSpanBuilder(tracer: self, spanName: spanName)
    }
}

class WrapperSpanBuilder: SpanBuilder {
    private var tracer: DatadogTracer
    private var isRootSpan: Bool = false
    private var spanContext: SpanContext?
    private var spanName: String

    init(tracer: DatadogTracer, spanName: String) {
        self.tracer = tracer
        self.spanName = spanName
    }

    @discardableResult public func startSpan() -> Span {
        if spanContext == nil, !isRootSpan {
            spanContext = OpenTelemetry.instance.contextProvider.activeSpan?.context
        }
        return WrapperSpan(name: spanName,
                           context: spanContext ?? SpanContext.create(traceId: TraceId.random(),
                                                                      spanId: SpanId.random(),
                                                                      traceFlags: TraceFlags(),
                                                                      traceState: TraceState()),
                              kind: .client,
                              tracer: tracer)
    }

    @discardableResult public func setParent(_ parent: Span) -> Self {
        spanContext = parent.context
        return self
    }

    @discardableResult public func setParent(_ parent: SpanContext) -> Self {
        spanContext = parent
        return self
    }

    @discardableResult public func setNoParent() -> Self {
        isRootSpan = true
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext) -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        return self
    }

    @discardableResult public func setSpanKind(spanKind: SpanKind) -> Self {
        return self
    }

    @discardableResult public func setStartTime(time: Date) -> Self {
        return self
    }

    public func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {

        return self
    }

    func setActive(_ active: Bool) -> Self {
        return self
    }
}

class NoOpSpan: Span {
    var kind: OpenTelemetryApi.SpanKind = .internal
    
    var name: String = ""
    
    var context: SpanContext = SpanContext.create(traceId: TraceId.invalid,
                                                  spanId: SpanId.invalid,
                                                  traceFlags: TraceFlags(),
                                                  traceState: TraceState())

    var isRecording: Bool = false

    var status: Status = Status.ok

    var description: String = "NoOpSpan"

    func updateName(name: String) {}

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {}

    func addEvent(name: String) {}

    func addEvent(name: String, timestamp: Date) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {}

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {}

    func end() {}

    func end(time: Date) {}
}

class NoOpSpanBuilder: SpanBuilder {
    @discardableResult public func startSpan() -> Span {
        return NoOpSpan()
    }

    @discardableResult public func setParent(_ parent: Span) -> Self {
        return self
    }

    @discardableResult public func setParent(_ parent: SpanContext) -> Self {
        return self
    }

    @discardableResult public func setNoParent() -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext) -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        return self
    }

    @discardableResult public func setSpanKind(spanKind: SpanKind) -> Self {
        return self
    }

    @discardableResult public func setStartTime(time: Date) -> Self {
        return self
    }

    public func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        return self
    }

    func setActive(_ active: Bool) -> Self {
        return self
    }
}

struct ConversionHelper {
    static func ToUInt64(from spanId: SpanId) -> UInt64 {
        var data = Data(count: 8)
        spanId.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    static func ToUInt64(from traceId: TraceId) -> UInt64 {
        var data = Data(count: 16)
        traceId.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }
}

extension SpanId {
    func toLong() -> UInt64 {
        var data = Data(count: 8)
        self.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    func toDatadogSpanID() -> DatadogInternal.SpanID {
        .init(integerLiteral: toLong())
    }
}


extension TraceId {
    func toLong() -> UInt64 {
        var data = Data(count: 16)
        self.copyBytesTo(dest: &data, destOffset: 0)
        return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
    }

    func toDatadogTraceID() -> DatadogInternal.TraceID {
        .init(integerLiteral: toLong())
    }
}

class WrapperSpan: OpenTelemetryApi.Span {
    var kind: OpenTelemetryApi.SpanKind
    var context: OpenTelemetryApi.SpanContext
    var name: String
    var nestedSpan: DDSpan

    func end() {
        end(time: Date())
    }

    func end(time: Date) {
        nestedSpan.finish(at: time)
    }

    /// Creates an instance of this class with the SpanContext, Span kind and name
    /// - Parameters:
    ///   - context: the SpanContext
    ///   - kind: the SpanKind
    init(name: String, context: SpanContext, kind: SpanKind, tracer: DatadogTracer) {
        self.nestedSpan = .init(tracer: tracer,
                                context: .init(traceID: context.traceId.toDatadogTraceID(),
                                               spanID: context.spanId.toDatadogSpanID(),
                                               parentSpanID: nil,
                                               baggageItems: .init()),
                                operationName: name,
                                startTime: Date(),
                                tags: [:])
        self.kind = .client
        self.context = context
        self.name = name
    }

    var isRecording: Bool {
        return false
    }

    var status: Status {
        get {
            return Status.ok
        }
        set {}
    }

    var description: String {
        return "WrapperSpan"
    }

    func updateName(name: String) {
        self.nestedSpan.setOperationName(name)
        self.name = name
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {
        self.nestedSpan.setTag(key: key, value: value)
    }

    func addEvent(name: String) {
        self.nestedSpan.log(fields: [name: ""])
    }

    func addEvent(name: String, timestamp: Date) {
        self.nestedSpan.log(fields: [name: ""], timestamp: timestamp)
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {
        self.nestedSpan.log(fields: attributes)
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {
        self.nestedSpan.log(fields: attributes, timestamp: timestamp)
    }
}
