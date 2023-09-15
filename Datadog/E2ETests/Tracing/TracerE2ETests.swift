/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogTrace

class TracerE2ETests: E2ETests {
    private var tracer: OTTracer { Tracer.shared() }

    /// - api-surface: OTTracer.startSpan(operationName: String,references: [OTReference]?,tags: [String: Encodable]?,startTime: Date?) -> OTSpan
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_tracer_start_span_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_tracer_start_span: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_tracer_start_span,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_tracer_start_span() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            _ = tracer.startSpan(operationName: .mockRandom()) // this span is never sent
        }
    }

    /// - api-surface: OTTracer.startRootSpan(operationName: String,tags: [String: Encodable]?,startTime: Date?) -> OTSpan
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_tracer_start_root_span_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_tracer_start_root_span: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_tracer_start_root_span,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_tracer_start_root_span() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            _ = tracer.startRootSpan(operationName: .mockRandom()) // this span is never sent
        }
    }

    /// - api-surface: OTTracer.inject(spanContext: OTSpanContext, writer: OTFormatWriter)
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_tracer_inject_span_context_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_tracer_inject_span_context: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_tracer_inject_span_context,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_tracer_inject_span_context() {
        let anySpan = tracer.startSpan(operationName: .mockRandom()) // this span is never sent
        let anyWriter = HTTPHeadersWriter()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            tracer.inject(spanContext: anySpan.context, writer: anyWriter)
        }
    }

    /// - api-surface: OTTracer.activeSpan: OTSpan?
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_tracer_active_span_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_tracer_active_span: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_tracer_active_span,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_tracer_active_span() {
        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            _ = tracer.activeSpan
        }
    }
}
