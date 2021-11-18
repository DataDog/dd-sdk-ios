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
    /// Builds the `Span` from user input.
    internal let spanBuilder: SpanEventBuilder
    /// Writes the `Span` to file.
    internal let spanOutput: SpanOutput
    /// Writes span logs to output. `nil` if Logging feature is disabled.
    internal let logOutput: LoggingForTracingAdapter.AdaptedLogOutput?
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    internal let queue: DispatchQueue
    /// Integration with RUM Context. `nil` if disabled for this Tracer or if the RUM feature disabled.
    internal let rumContextIntegration: TracingWithRUMContextIntegration?
    /// Integration with Span context injected by environment.
    internal let environmentSpanIntegration = TracingWithEnvironmentSpanIntegration()

    private let dateProvider: DateProvider
    private let tracingUUIDGenerator: TracingUUIDGenerator

    /// Tags to be set on all spans. They are set at initialization from Tracer.Configuration
    private let globalTags: [String: Encodable]?

    internal let activeSpansPool = ActiveSpansPool()

    // MARK: - Initialization

    /// Initializes the Datadog Tracer.
    /// - Parameters:
    ///   - configuration: the tracer configuration obtained using `Tracer.Configuration()`.
    public static func initialize(configuration: Configuration) -> OTTracer {
        do {
            if Global.sharedTracer is Tracer {
                throw ProgrammerError(
                    description: """
                    The `Tracer` instance was already created. Use existing `Global.sharedTracer` instead of initializing the `Tracer` another time.
                    """
                )
            }
            guard let tracingFeature = TracingFeature.instance else {
                throw ProgrammerError(
                    description: Datadog.instance == nil
                        ? "`Datadog.initialize()` must be called prior to `Tracer.initialize()`."
                        : "`Tracer.initialize(configuration:)` produces a non-functional tracer, as the tracing feature is disabled."
                )
            }
            return DDTracer(
                tracingFeature: tracingFeature,
                tracerConfiguration: configuration
            )
        } catch {
            consolePrint("\(error)")
            return DDNoopTracer()
        }
    }

    internal convenience init(tracingFeature: TracingFeature, tracerConfiguration: Configuration) {
        self.init(
            spanBuilder: SpanEventBuilder(
                sdkVersion: tracingFeature.configuration.common.sdkVersion,
                applicationVersion: tracingFeature.configuration.common.applicationVersion,
                serviceName: tracerConfiguration.serviceName ?? tracingFeature.configuration.common.serviceName,
                userInfoProvider: tracingFeature.userInfoProvider,
                networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.networkConnectionInfoProvider : nil,
                carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.carrierInfoProvider : nil,
                dateCorrector: tracingFeature.dateCorrector,
                source: tracingFeature.configuration.common.source,
                eventsMapper: tracingFeature.configuration.spanEventMapper
            ),
            spanOutput: SpanFileOutput(
                fileWriter: tracingFeature.storage.writer,
                environment: tracingFeature.configuration.common.environment
            ),
            logOutput: tracingFeature
                .loggingFeatureAdapter?
                .resolveLogOutput(usingTracingFeature: tracingFeature, tracerConfiguration: tracerConfiguration),
            dateProvider: tracingFeature.dateProvider,
            tracingUUIDGenerator: tracingFeature.tracingUUIDGenerator,
            globalTags: tracerConfiguration.globalTags,
            rumContextIntegration: (RUMFeature.isEnabled && tracerConfiguration.bundleWithRUM) ? TracingWithRUMContextIntegration() : nil
        )
    }

    internal init(
        spanBuilder: SpanEventBuilder,
        spanOutput: SpanOutput,
        logOutput: LoggingForTracingAdapter.AdaptedLogOutput?,
        dateProvider: DateProvider,
        tracingUUIDGenerator: TracingUUIDGenerator,
        globalTags: [String: Encodable]?,
        rumContextIntegration: TracingWithRUMContextIntegration?
    ) {
        self.spanBuilder = spanBuilder
        self.spanOutput = spanOutput
        self.logOutput = logOutput
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )
        self.dateProvider = dateProvider
        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.globalTags = globalTags
        self.rumContextIntegration = rumContextIntegration
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
            traceID: parentSpanContext?.traceID ?? (environmentSpanIntegration.environmentSpanContext?.traceID ?? tracingUUIDGenerator.generateUnique()),
            spanID: tracingUUIDGenerator.generateUnique(),
            parentSpanID: parentSpanContext?.spanID ?? environmentSpanIntegration.environmentSpanContext?.spanID,
            baggageItems: BaggageItems(targetQueue: queue, parentSpanItems: parentSpanContext?.baggageItems)
        )
    }

    internal func startSpan(spanContext: DDSpanContext, operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> OTSpan {
        var combinedTags = globalTags ?? [:]
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
            startTime: startTime ?? dateProvider.currentDate(),
            tags: combinedTags
        )
        return span
    }
}
