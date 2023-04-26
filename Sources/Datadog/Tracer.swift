/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Datadog - specific span `tags` to be used with `tracer.startSpan(operationName:references:tags:startTime:)`
/// and `span.setTag(key:value:)`.
public struct DDTags {
    /// A Datadog-specific span tag, which sets the value appearing in the "RESOURCE" column
    /// in traces explorer on [app.datadoghq.com](https://app.datadoghq.com/)
    /// Can be used to customize the resource names grouped under the same operation name.
    ///
    /// Expects `String` value set for a tag.
    public static let resource = "resource.name"
    /// Internal tag. `Integer` value. Measures elapsed time at app's foreground state in nanoseconds.
    /// (duration - foregroundDuration) gives you the elapsed time while the app wasn't active (probably at background)
    internal static let foregroundDuration = "foreground_duration"
    /// Internal tag. `Bool` value.
    /// `true` if span was started or ended while the app was not active, `false` otherwise.
    internal static let isBackground = "is_background"

    /// Those keys used to encode information received from the user through `OpenTracingLogFields`, `OpenTracingTagKeys` or custom fields.
    /// Supported by Datadog platform.
    internal static let errorType    = "error.type"
    internal static let errorMessage = "error.msg"
    internal static let errorStack   = "error.stack"
}

/// Because `Tracer` is a common name widely used across different projects, the `Datadog.Tracer` may conflict when
/// doing `import Datadog`. In such case, following `DDTracer` typealias can be used to avoid compiler ambiguity.
///
/// Usage:
///
///     import Datadog
///
///     // tracer reference
///     var tracer: DDTracer!
///
///     // instantiate Datadog tracer
///     tracer = DDTracer.initialize(...)
///
public typealias DDTracer = Tracer

public class Tracer: OTTracer {
    internal let core: DatadogCoreProtocol

    /// The Tracer configuration
    internal let configuration: Configuration
    /// Span events mapper configured by the user, `nil` if not set.
    internal let spanEventMapper: SpanEventMapper?
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    internal let queue: DispatchQueue
    /// Integration with RUM Context. `nil` if disabled for this Tracer or if the RUM feature is disabled.
    internal let rumIntegration: TracingWithRUMIntegration?
    /// Integration with Logging.
    internal let loggingIntegration: TracingWithLoggingIntegration

    private let tracingUUIDGenerator: TracingUUIDGenerator

    /// Date provider for traces.
    private let dateProvider: DateProvider

    internal let activeSpansPool = ActiveSpansPool()

    internal let sampler: Sampler

    /// Tracer Attributes shared with other Feature registered in core.
    internal struct Attributes {
        internal static let traceID = "dd.trace_id"
        internal static let spanID = "dd.span_id"
    }

    // MARK: - Initialization

    /// Initializes the Datadog Tracer.
    /// - Parameters:
    ///   - configuration: the tracer configuration obtained using `Tracer.Configuration()`.
    public static func initialize(configuration: Configuration, in core: DatadogCoreProtocol = defaultDatadogCore) -> OTTracer {
        do {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `Tracer.initialize()`."
                )
            }
            if Global.sharedTracer is Tracer {
                throw ProgrammerError(
                    description: """
                    The `Tracer` instance was already created. Use existing `Global.sharedTracer` instead of initializing the `Tracer` another time.
                    """
                )
            }
            guard let tracingFeature = core.v1.feature(TracingFeature.self) else {
                throw ProgrammerError(
                    description: "`Tracer.initialize(configuration:)` produces a non-functional tracer, as the tracing feature is disabled."
                )
            }
            return DDTracer(
                core: core,
                tracingFeature: tracingFeature,
                tracerConfiguration: configuration
            )
        } catch {
            consolePrint("\(error)")
            return DDNoopTracer()
        }
    }

    internal convenience init(
        core: DatadogCoreProtocol,
        tracingFeature: TracingFeature,
        tracerConfiguration: Configuration
    ) {
        self.init(
            core: core,
            configuration: tracerConfiguration,
            spanEventMapper: tracingFeature.configuration.spanEventMapper,
            tracingUUIDGenerator: tracingFeature.configuration.uuidGenerator,
            dateProvider: tracingFeature.configuration.dateProvider,
            rumIntegration: tracerConfiguration.bundleWithRUM ? (tracingFeature.messageReceiver as? TracingMessageReceiver)?.rum : nil,
            loggingIntegration: TracingWithLoggingIntegration(
                core: core,
                tracerConfiguration: tracerConfiguration
            )
        )
    }

    internal init(
        core: DatadogCoreProtocol,
        configuration: Configuration,
        spanEventMapper: SpanEventMapper?,
        tracingUUIDGenerator: TracingUUIDGenerator,
        dateProvider: DateProvider,
        rumIntegration: TracingWithRUMIntegration?,
        loggingIntegration: TracingWithLoggingIntegration
    ) {
        self.core = core
        self.configuration = configuration
        self.spanEventMapper = spanEventMapper
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )

        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.dateProvider = dateProvider
        self.rumIntegration = rumIntegration
        self.loggingIntegration = loggingIntegration
        self.sampler = Sampler(samplingRate: configuration.samplingRate)
    }

    // MARK: - Open Tracing interface

    public func startSpan(operationName: String, references: [OTReference]? = nil, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        let parentSpanContext = references?.compactMap { $0.context.dd }.last ?? activeSpan?.context as? DDSpanContext
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: parentSpanContext),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    public func startRootSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        return startSpan(
            spanContext: createSpanContext(parentSpanContext: nil),
            operationName: operationName,
            tags: tags,
            startTime: startTime
        )
    }

    public func inject(spanContext: OTSpanContext, writer: OTFormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    public func extract(reader: OTFormatReader) -> OTSpanContext? {
        // TODO: RUMM-385 - make `HTTPHeadersReader` available in public API
        if let reader = reader as? TracePropagationHeadersExtractor {
            reader.use(baggageItemQueue: queue)
            return reader.extract()
        } else {
            return nil
        }
    }

    public var activeSpan: OTSpan? {
        return activeSpansPool.getActiveSpan()
    }

    // MARK: - Internal

    internal func createSpanContext(parentSpanContext: DDSpanContext? = nil) -> DDSpanContext {
        return DDSpanContext(
            traceID: parentSpanContext?.traceID ?? tracingUUIDGenerator.generateUnique(),
            spanID: tracingUUIDGenerator.generateUnique(),
            parentSpanID: parentSpanContext?.spanID,
            baggageItems: BaggageItems(targetQueue: queue, parentSpanItems: parentSpanContext?.baggageItems)
        )
    }

    internal func startSpan(spanContext: DDSpanContext, operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        var combinedTags = configuration.globalTags ?? [:]
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        if let rumTags = rumIntegration?.attributes {
            combinedTags.merge(rumTags) { $1 }
        }

        let span = DDSpan(
            tracer: self,
            context: spanContext,
            operationName: operationName,
            startTime: startTime ?? dateProvider.now,
            tags: combinedTags
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

        core.set(feature: "tracing", attributes: {[
            Attributes.traceID: context.map { $0.traceID.toString(.decimal) },
            Attributes.spanID: context.map { $0.spanID.toString(.decimal) }
        ]})
    }
}
