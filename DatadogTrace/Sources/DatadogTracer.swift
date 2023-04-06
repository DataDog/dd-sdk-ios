/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Datadog - specific span `tags` to be used with `tracer.startSpan(operationName:references:tags:startTime:)`
/// and `span.setTag(key:value:)`.
public enum DatadogSpanTag {
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
public class DatadogTracer: OTTracer {
    internal weak var core: DatadogCoreProtocol?

    /// The Tracer configuration
    internal let configuration: Configuration
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    internal let queue: DispatchQueue
    /// Integration with Core Context.
    internal let contextReceiver: ContextMessageReceiver
    /// Integration with Logging.
    internal let loggingIntegration: TracingWithLoggingIntegration

    private let tracingUUIDGenerator: TraceIDGenerator

    /// Date provider for traces.
    private let dateProvider: DateProvider

    internal let activeSpansPool = ActiveSpansPool()

    /// Tracer Attributes shared with other Feature registered in core.
    internal struct Attributes {
        internal static let traceID = "dd.trace_id"
        internal static let spanID = "dd.span_id"
    }

    // MARK: - Initialization

    /// Initializes the Datadog Tracer.
    /// - Parameters:
    ///   - configuration: the tracer configuration obtained using `Tracer.Configuration()`.

    /// Initializes the Datadog Tracer.
    ///
    /// - Parameters:
    ///   - core: The core instance in which to register the Feature.
    ///   - configuration: The Tracer configuration.
    ///   - distributedTracingConfiguration: Distributed Tracing configuration. **Do not use this configuration if you intend to use RUM, configure Distributed Tracing in RUM instead**
    ///   - dateProvider: The date provider.
    ///   - traceIDGenerator: The trace ID generator.
    public static func initialize(
        in core: DatadogCoreProtocol = defaultDatadogCore,
        configuration: Configuration = .init(),
        distributedTracingConfiguration: DistributedTracingConfiguration? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator()
    ) {
        do {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `DatadogTracer.initialize()`."
                )
            }

            let contextReceiver = ContextMessageReceiver(bundleWithRUM: configuration.bundleWithRUM)

            let tracer = DatadogTracer(
                core: core,
                configuration: configuration,
                tracingUUIDGenerator: traceIDGenerator,
                dateProvider: dateProvider,
                contextReceiver: contextReceiver,
                loggingIntegration: TracingWithLoggingIntegration(
                    core: core,
                    tracerConfiguration: configuration
                )
            )

            let feature = DatadogTraceFeature(
                tracer: tracer,
                requestBuilder: TracingRequestBuilder(
                    customIntakeURL: configuration.customIntakeURL
                ),
                messageReceiver: contextReceiver
            )

            try core.register(feature: feature)

            if let config = distributedTracingConfiguration {
                let handler = TracingURLSessionHandler(
                    tracer: tracer,
                    contextReceiver: contextReceiver,
                    distributedTracingConfiguration: config
                )

                try core.register(urlSessionHandler: handler)
            }

            TelemetryCore(core: core)
                .configuration(useTracing: true)
        } catch {
            consolePrint("\(error)")
        }
    }

    public static func shared(in core: DatadogCoreProtocol = defaultDatadogCore) -> OTTracer {
        do {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `DatadogTracer.initialize()`."
                )
            }

            guard let feature = core.get(feature: DatadogTraceFeature.self) else {
                throw ProgrammerError(
                    description: "`DatadogTracer.initialize()` must be called prior to `DatadogTracer.shared()`."
                )
            }

            return feature.tracer
        } catch {
            consolePrint("\(error)")
            return DDNoopTracer()
        }
    }

    internal required init(
        core: DatadogCoreProtocol,
        configuration: Configuration,
        tracingUUIDGenerator: TraceIDGenerator,
        dateProvider: DateProvider,
        contextReceiver: ContextMessageReceiver,
        loggingIntegration: TracingWithLoggingIntegration
    ) {
        self.core = core
        self.configuration = configuration
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )

        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.dateProvider = dateProvider
        self.contextReceiver = contextReceiver
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
        reader.extract()
    }

    public var activeSpan: OTSpan? {
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
        var combinedTags = configuration.globalTags ?? [:]
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

        core?.set(feature: DatadogTraceFeature.name, attributes: {[
            Attributes.traceID: context.map { String($0.traceID) },
            Attributes.spanID: context.map { String($0.spanID) }
        ]})
    }
}
