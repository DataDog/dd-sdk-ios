/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk

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
public class DatadogTracer {
    let otelTracer: Tracer

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

    internal let sampler: DatadogInternal.Sampler

    /// Tracer Attributes shared with other Feature registered in core.
    internal enum Attributes {
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

    public static func shared(in core: DatadogCoreProtocol = defaultDatadogCore) -> DatadogTracer {
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
            return DDNoopTracer() as! DatadogTracer
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
        self.sampler = Sampler(samplingRate: configuration.samplingRate)

        let spanProcessor = SimpleSpanProcessor(spanExporter: InMemoryExporter())
        let tracerProviderSdk = TracerProviderBuilder().with(sampler: Samplers.alwaysOn)
            .add(spanProcessor: spanProcessor)
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProviderSdk)
        otelTracer = tracerProviderSdk.get(instrumentationName: "com.datadoghq.DatadogTracer", instrumentationVersion: "0.1") as! TracerSdk
    }

    // MARK: - Open Tracing interface

    public func startSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> Span {
        return startSpan(
            operationName: operationName,
            tags: tags,
            startTime: startTime,
            isRoot: false
        )
    }

    public func startRootSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil) -> Span {
        return startSpan(
            operationName: operationName,
            tags: tags,
            startTime: startTime,
            isRoot: true
        )
    }

    public func inject(spanContext: OTSpanContext, writer: OTFormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    public func extract(reader: OTFormatReader) -> OTSpanContext? {
        // TODO: RUMM-385 - make `HTTPHeadersReader` available in public API
        reader.extract()
    }

    public var activeSpan: Span? {
        return OpenTelemetry.instance.contextProvider.activeSpan
    }

    // MARK: - Internal

    internal func startSpan(operationName: String, tags: [String: Encodable]? = nil, startTime: Date? = nil, isRoot: Bool) -> Span {
        var combinedTags = configuration.globalTags ?? [:]
        if let userTags = tags {
            combinedTags.merge(userTags) { $1 }
        }

        if let rumTags = contextReceiver.context.rum {
            combinedTags.merge(rumTags) { $1 }
        }

        let spanBuilder = otelTracer.spanBuilder(spanName: operationName)
        if let tags = tags {
            let attributes = DatadogTracer.convertToAttributes(tags: tags)
            attributes.forEach {
                spanBuilder.setAttribute(key: $0.key, value: $0.value)
            }
        }
        if let startTime = startTime {
            spanBuilder.setStartTime(time: startTime)
        }
        if isRoot {
            spanBuilder.setNoParent()
        }
        spanBuilder.setActive(true)
        let span = spanBuilder.startSpan()
        return span
    }

    private func updateCoreAttributes() {
        let context = activeSpan?.context as? DDSpanContext

        core?.set(feature: DatadogTraceFeature.name, attributes: { [
            Attributes.traceID: context.map { String($0.traceID) },
            Attributes.spanID: context.map { String($0.spanID) }
        ] })
    }

    static func convertToAttributes(tags: [String: Encodable]) -> [String: OpenTelemetryApi.AttributeValue] {
        let attributes: [String: OpenTelemetryApi.AttributeValue] = tags.mapValues { value in
            convertToAttributeValue(tag: value)
        }
        return attributes
    }

    static func convertToAttributeValue(tag: Encodable) -> OpenTelemetryApi.AttributeValue {
        switch tag {
        case let string as String:
            return OpenTelemetryApi.AttributeValue.string(string)
        case let int as Int:
            return OpenTelemetryApi.AttributeValue.int(int)
        case let double as Double:
            return OpenTelemetryApi.AttributeValue.double(double)
        case let bool as Bool:
            return OpenTelemetryApi.AttributeValue.bool(bool)
        default:
            return OpenTelemetryApi.AttributeValue.string("")
        }
    }
}
