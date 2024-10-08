/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

import DatadogInternal
import DatadogBenchmarks

internal final class Profiler: DatadogInternal.BenchmarkProfiler {
    func tracer(operation: @autoclosure () -> String) -> any DatadogInternal.BenchmarkTracer {
        DummyTracer()
    }
}

internal final class DummyTracer: DatadogInternal.BenchmarkTracer {
    func startSpan(named: @autoclosure () -> String) -> any DatadogInternal.BenchmarkSpan {
        DummySpan()
    }
}

internal final class DummySpan: DatadogInternal.BenchmarkSpan {
    func stop() { }
}
