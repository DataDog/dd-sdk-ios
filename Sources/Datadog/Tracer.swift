/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
    internal let rumContextIntegration: TracingWithRUMContextIntegration?
    /// Integration with Logging. `nil` if the Logging feature is disabled.
    internal let loggingIntegration: TracingWithLoggingIntegration?

    private let tracingUUIDGenerator: TracingUUIDGenerator

    internal let activeSpansPool = ActiveSpansPool()

    // MARK: - Initialization

    /// Initializes the Datadog Tracer.
    /// - Parameters:
    ///   - configuration: the tracer configuration obtained using `Tracer.Configuration()`.
    public static func initialize(configuration: Configuration, in core: DatadogCoreProtocol = defaultDatadogCore) -> OTTracer {
        do {
            guard let context = core.v1.context else {
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
                tracerConfiguration: configuration,
                rumEnabled: core.v1.feature(RUMFeature.self) != nil,
                loggingFeature: core.v1.feature(LoggingFeature.self),
                context: context
            )
        } catch {
            consolePrint("\(error)")
            return DDNoopTracer()
        }
    }

    internal convenience init(
        core: DatadogCoreProtocol,
        tracingFeature: TracingFeature,
        tracerConfiguration: Configuration,
        rumEnabled: Bool,
        loggingFeature: LoggingFeature?,
        context: DatadogV1Context
    ) {
        self.init(
            core: core,
            configuration: tracerConfiguration,
            spanEventMapper: tracingFeature.configuration.spanEventMapper,
            tracingUUIDGenerator: tracingFeature.configuration.uuidGenerator,
            rumContextIntegration: (rumEnabled && tracerConfiguration.bundleWithRUM) ? TracingWithRUMContextIntegration() : nil,
            loggingIntegration: loggingFeature.map {
                TracingWithLoggingIntegration(
                    core: core,
                    context: context,
                    tracerConfiguration: tracerConfiguration,
                    loggingFeature: $0
                )
            }
        )
    }

    internal init(
        core: DatadogCoreProtocol,
        configuration: Configuration,
        spanEventMapper: SpanEventMapper?,
        tracingUUIDGenerator: TracingUUIDGenerator,
        rumContextIntegration: TracingWithRUMContextIntegration?,
        loggingIntegration: TracingWithLoggingIntegration?
    ) {
        self.core = core
        self.configuration = configuration
        self.spanEventMapper = spanEventMapper
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )

        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.rumContextIntegration = rumContextIntegration
        self.loggingIntegration = loggingIntegration
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
        guard let reader = reader as? HTTPHeadersReader else {
            return nil
        }
        reader.use(baggageItemQueue: queue)
        return reader.extract()
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
            combinedTags.merge(userTags) { _, last in last }
        }
        if let currentRUMContextTags = rumContextIntegration?.currentRUMContextTags {
            combinedTags.merge(currentRUMContextTags) { _, last in last }
        }

        let span = DDSpan(
            tracer: self,
            context: spanContext,
            operationName: operationName,
            startTime: startTime ?? core.v1.context?.dateProvider.now ?? Date(),
            tags: combinedTags
        )
        return span
    }
}
