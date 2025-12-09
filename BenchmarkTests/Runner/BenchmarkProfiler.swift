/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Lightweight profiler that prints span timing to console.
/// Retains the profiling interface for future instrumentation without OTel dependency.
internal final class Profiler: BenchmarkProfiler {
    func tracer(operation: @autoclosure () -> String) -> any BenchmarkTracer {
        Tracer(operationName: operation())
    }
}

private final class Tracer: BenchmarkTracer {
    let operationName: String

    init(operationName: String) {
        self.operationName = operationName
    }

    func startSpan(named: @autoclosure () -> String) -> any BenchmarkSpan {
        Span(operation: operationName, name: named())
    }
}

private final class Span: BenchmarkSpan {
    let operation: String
    let name: String
    let startTime: CFAbsoluteTime

    init(operation: String, name: String) {
        self.operation = operation
        self.name = name
        self.startTime = CFAbsoluteTimeGetCurrent()
    }

    func stop() {
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1_000
        print("⏱ [\(operation)/\(name)] \(String(format: "%.2f", durationMs))ms")
    }
}
