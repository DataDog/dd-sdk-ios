/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog

class SpanE2ETests: E2ETests {
    /// - api-surface: OTSpan.setOperationName(_ operationName: String)
    ///
    /// - data monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_operation_name_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_set_operation_name: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:trace.trace_span_set_operation_name.hits{service:com.datadog.ios.nightly,env:instrumentation}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_operation_name_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_set_operation_name: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_set_operation_name,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_set_operation_name() {
        let span = Global.sharedTracer.startSpan(operationName: .mockRandom())
        let knownOperationName = "trace_span_set_operation_name_new_operation_name" // asserted in monitor

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.setOperationName(knownOperationName)
        }

        span.finish()
    }

    /// - api-surface: OTSpan.setTag(key: String, value: Encodable)
    ///
    /// - data monitor: (it uses `ios_trace_span_set_tag` metric defined in "APM > Generate Metrics > Custom Span Metrics")
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_tag_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_set_tag: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:ios_trace_span_set_tag.hits_with_proper_payload{*}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_tag_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_set_tag: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_set_tag,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_set_tag() {
        let span = Global.sharedTracer.startSpan(operationName: "ios_trace_span_set_tag")
        let knownTag = DD.specialTag()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.setTag(key: knownTag.key, value: knownTag.value)
        }

        span.finish()
    }

    /// - api-surface: OTSpan.setBaggageItem(key: String, value: String)
    ///
    /// - data monitor: (it uses `ios_trace_span_set_baggage_item` metric defined in "APM > Generate Metrics > Custom Span Metrics")
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_baggage_item_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_set_baggage_item: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:ios_trace_span_set_baggage_item.hits_with_proper_payload{*}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_baggage_item_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_set_baggage_item: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_set_baggage_item,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_set_baggage_item() {
        let span = Global.sharedTracer.startSpan(operationName: "ios_trace_span_set_baggage_item")
        let knownTag = DD.specialTag()

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.setBaggageItem(key: knownTag.key, value: knownTag.value)
        }

        span.finish()
    }

    /// - api-surface: OTTracer.activeSpan: OTSpan?
    ///
    /// - data monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_active_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_set_active: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:trace.trace_span_set_active_measured_span.hits{service:com.datadog.ios.nightly,env:instrumentation}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_set_active_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_set_active: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_set_active,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_set_active() {
        let span = Global.sharedTracer.startSpan(operationName: "trace_span_set_active_measured_span")

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.setActive()
        }

        span.finish()
    }

    /// - api-surface: OTTracer.log(fields: [String: Encodable], timestamp: Date)
    ///
    /// - data monitor:
    /// ```logs
    /// $feature = trace
    /// $monitor_id = trace_span_log_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_log: number of hits is below expected value"
    /// $monitor_query = "logs(\"service:com.datadog.ios.nightly @test_method_name:trace_span_log @test_special_string_attribute:customAttribute*\").index(\"*\").rollup(\"count\").last(\"1d\") < 1"
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_log_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_log: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_log,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_log() {
        let span = Global.sharedTracer.startSpan(operationName: "trace_span_log_measured_span")
        let log = DD.specialStringAttribute()

        var fields = DD.logAttributes()
        fields[log.key] = log.value

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.log(fields: fields)
        }

        span.finish()
    }

    /// - api-surface: OTTracer.finish(at time: Date)
    ///
    /// - data monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_finish_data
    /// $monitor_name = "[RUM] [iOS] Nightly - trace_span_finish: number of hits is below expected value"
    /// $monitor_query = "sum(last_1d):avg:trace.trace_span_finish_measured_span.hits{service:com.datadog.ios.nightly,env:instrumentation}.as_count() < 1"
    /// $monitor_threshold = 1
    /// ```
    ///
    /// - performance monitor:
    /// ```apm
    /// $feature = trace
    /// $monitor_id = trace_span_finish_performance
    /// $monitor_name = "[RUM] [iOS] Nightly Performance - trace_span_finish: has a high average execution time"
    /// $monitor_query = "avg(last_1d):p50:trace.perf_measure{env:instrumentation,resource_name:trace_span_finish,service:com.datadog.ios.nightly} > 0.024"
    /// ```
    func test_trace_span_finish() {
        let span = Global.sharedTracer.startSpan(operationName: "trace_span_finish_measured_span")

        measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            span.finish()
        }
    }
}
