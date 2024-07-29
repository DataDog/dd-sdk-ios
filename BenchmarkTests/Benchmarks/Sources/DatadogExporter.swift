/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if OTEL_API
#error("Benchmarks depends on opentelemetry-swift. Please open the project with 'make benchmark-tests-open'.")
#endif

#if OTEL_SWIFT
import OpenTelemetrySdk

public final class DatadogExporter: SpanExporter, MetricExporter {
    private let session: URLSession
    
    public convenience init() {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.init(session: URLSession(configuration: configuration))
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func export(spans: [SpanData]) -> SpanExporterResultCode {
        return .success
    }

    public func export(metrics: [Metric], shouldCancel: (() -> Bool)?) -> MetricExporterResultCode {
        return .success
    }

    public func flush() -> SpanExporterResultCode {
        return .success
    }

    public func shutdown() {

    }
}

#endif
