/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
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
}

public class DDTracer: Tracer {
    /// Writes `Span` objects to output.
    internal let spanOutput: SpanOutput
    /// Writes span logs to output.
    /// Equals `nil` if Logging feature is disabled.
    internal let logOutput: LoggingForTracingAdapter.AdaptedLogOutput?
    /// Queue ensuring thread-safety of the `DDTracer` and `DDSpan` operations.
    internal let queue: DispatchQueue

    private let dateProvider: DateProvider
    private let tracingUUIDGenerator: TracingUUIDGenerator

    // MARK: - Initialization

    /// Initializes the Datadog Tracer.
    /// - Parameters:
    ///   - configuration: the tracer configuration obtained using `DDTracer.Configuration()`.
    public static func initialize(configuration: Configuration) -> OpenTracing.Tracer {
        do {
            return try initializeOrThrow(configuration: configuration)
        } catch {
            consolePrint("\(error)")
            return DDNoopTracer()
        }
    }

    internal static func initializeOrThrow(configuration: Configuration) throws -> DDTracer {
        guard let tracingFeature = TracingFeature.instance else {
            throw ProgrammerError(
                description: Datadog.instance == nil
                    ? "`Datadog.initialize()` must be called prior to `DDTracer.initialize()`."
                    : "`DDTracer.initialize(configuration:)` produces a non-functional tracer, as the tracing feature is disabled."
            )
        }
        return DDTracer(
            tracingFeature: tracingFeature,
            tracerConfiguration: configuration
        )
    }

    internal convenience init(tracingFeature: TracingFeature, tracerConfiguration: Configuration) {
        self.init(
            spanOutput: SpanFileOutput(
                spanBuilder: SpanBuilder(
                    applicationVersion: tracingFeature.configuration.applicationVersion,
                    environment: tracingFeature.configuration.environment,
                    serviceName: tracerConfiguration.serviceName ?? tracingFeature.configuration.serviceName,
                    userInfoProvider: tracingFeature.userInfoProvider,
                    networkConnectionInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.networkConnectionInfoProvider : nil,
                    carrierInfoProvider: tracerConfiguration.sendNetworkInfo ? tracingFeature.carrierInfoProvider : nil
                ),
                fileWriter: tracingFeature.storage.writer
            ),
            logOutput: tracingFeature
                .loggingFeatureAdapter?
                .resolveLogOutput(usingTracingFeature: tracingFeature, tracerConfiguration: tracerConfiguration),
            dateProvider: tracingFeature.dateProvider,
            tracingUUIDGenerator: tracingFeature.tracingUUIDGenerator
        )
    }

    internal init(
        spanOutput: SpanOutput,
        logOutput: LoggingForTracingAdapter.AdaptedLogOutput?,
        dateProvider: DateProvider,
        tracingUUIDGenerator: TracingUUIDGenerator
    ) {
        self.spanOutput = spanOutput
        self.logOutput = logOutput
        self.queue = DispatchQueue(
            label: "com.datadoghq.tracer",
            target: .global(qos: .userInteractive)
        )
        self.dateProvider = dateProvider
        self.tracingUUIDGenerator = tracingUUIDGenerator
    }

    // MARK: - Open Tracing interface

    public func startSpan(operationName: String, references: [Reference]? = nil, tags: [String: Codable]? = nil, startTime: Date? = nil) -> OpenTracing.Span {
        do {
            return try startSpanOrThrow(operationName: operationName, references: references, tags: tags, startTime: startTime)
        } catch {
            consolePrint("\(error)")
            return DDNoopSpan()
        }
    }

    public func inject(spanContext: SpanContext, writer: FormatWriter) {
        writer.inject(spanContext: spanContext)
    }

    public func extract(reader: FormatReader) -> SpanContext? {
        // TODO: RUMM-385 - we don't need to support it now
        return nil
    }

    // MARK: - Private Open Tracing helpers

    private func startSpanOrThrow(operationName: String, references: [Reference]?, tags: [String: Codable]?, startTime: Date?) throws -> OpenTracing.Span {
        let parentSpanContext = references?.compactMap { $0.context.dd }.last
        return DDSpan(
            tracer: self,
            context: DDSpanContext(
                traceID: parentSpanContext?.traceID ?? tracingUUIDGenerator.generateUnique(),
                spanID: tracingUUIDGenerator.generateUnique(),
                parentSpanID: parentSpanContext?.spanID,
                baggageItems: BaggageItems(targetQueue: queue, parentSpanItems: parentSpanContext?.baggageItems)
            ),
            operationName: operationName,
            startTime: startTime ?? dateProvider.currentDate(),
            tags: tags ?? [:]
        )
    }

    // MARK: - Internal

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
