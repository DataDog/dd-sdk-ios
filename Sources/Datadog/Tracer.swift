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
    /// Writes `Span` objects to output.
    internal let spanOutput: SpanOutput
    /// Writes span logs to output.
    /// Equals `nil` if Logging feature is disabled.
    internal let logOutput: LoggingForTracingAdapter.AdaptedLogOutput?
    /// Queue ensuring thread-safety of the `Tracer` and `DDSpan` operations.
    internal let queue: DispatchQueue
    /// Integration with RUM Context. `nil` if disabled for this Tracer or if the RUM feature disabled.
    internal let rumContextIntegration: TracingWithRUMContextIntegration?

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
            spanOutput: SpanFileOutput(
                spanBuilder: SpanBuilder(
                    applicationVersion: tracingFeature.configuration.common.applicationVersion,
                    environment: tracingFeature.configuration.common.environment,
                    serviceName: tracerConfiguration.serviceName ?? tracingFeature.configuration.common.serviceName,
                    userInfoProvider: tracingFeature.userInfoProvider,
                    networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.networkConnectionInfoProvider : nil,
                    carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.carrierInfoProvider : nil,
                    dateCorrection: tracingFeature.dateCorrection
                ),
                fileWriter: tracingFeature.storage.writer
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
        spanOutput: SpanOutput,
        logOutput: LoggingForTracingAdapter.AdaptedLogOutput?,
        dateProvider: DateProvider,
        tracingUUIDGenerator: TracingUUIDGenerator,
        globalTags: [String: Encodable]?,
        rumContextIntegration: TracingWithRUMContextIntegration?
    ) {
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
            traceID: parentSpanContext?.traceID ?? tracingUUIDGenerator.generateUnique(),
            spanID: tracingUUIDGenerator.generateUnique(),
            parentSpanID: parentSpanContext?.spanID,
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

    internal func write(span: DDSpan, finishTime: Date) {
        spanOutput.write(ddspan: span, finishTime: finishTime)
    }

    internal func writeLog(for span: DDSpan, fields: [String: Encodable], date: Date) {
        guard let logOutput = logOutput else {
            userLogger.warn("The log for span \"\(span.operationName)\" will not be send, because the Logging feature is disabled.")
            return
        }
        logOutput.writeLog(withSpanContext: span.ddContext, fields: fields, date: date)
    }
}
