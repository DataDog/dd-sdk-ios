/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if BENCHMARK
/// The profiler endpoint to collect data for benchmarking.
public var profiler: BenchmarkProfiler = NOPBenchmarkProfiler()
#else
/// The profiler endpoint to collect data for benchmarking. This static variable can only
/// be mutated in the benchmark environment.
public let profiler: BenchmarkProfiler = NOPBenchmarkProfiler()
#endif

/// The Benchmark Profiler provides interfaces to collect data in a benchmark
/// environment.
///
/// During benchmarking, a concrete implementation of the profiler will be
/// injected to collect data during execution of the SDK.
///
/// In production, the profiler is no-op and immutable.
public protocol BenchmarkProfiler {
    /// Returns a `BenchmarkTracer` instance for the given operation.
    ///
    /// The profiler must return the same instance of a tracer for the same operation.
    /// - Parameter operation: The tracer operation name. The parameter is an auto-closure
    /// to not intialise the value if the profiler is no-op.
    /// - Returns: The tracer instance.
    func tracer(operation: @autoclosure () -> String) -> BenchmarkTracer
}

/// The Benchmark Tracer will create and start spans in a benchmark environment.
/// This tracer can be used to measure CPU Time of inner operation of the SDK.
/// In production, the Benchmark Tracer is no-op.
public protocol BenchmarkTracer {
    /// Create and starts a span at the current time..
    ///
    /// The span will be activated automatically and linked to its parent in this tracer context.
    ///
    /// - Parameter named: The span name. The parameter is an auto-closure
    /// to not intialise the value if the profiler is no-op.
    /// - Returns: The started span.
    func startSpan(named: @autoclosure () -> String) -> BenchmarkSpan
}

/// A timespan of an operation in a benchmark environment.
public protocol BenchmarkSpan {
    /// Stops the span at the current time.
    func stop()
}

private final class NOPBenchmarkProfiler: BenchmarkProfiler {
    /// Returns no-op tracer shared instance.
    func tracer(operation: @autoclosure () -> String) -> BenchmarkTracer {
        NOPBenchmarkTracer.shared
    }
}

private final class NOPBenchmarkTracer: BenchmarkTracer {
    /// The no-op tracer shared instance.
    static let shared: BenchmarkTracer = NOPBenchmarkTracer()

    /// Returns no-op span shared instance.
    func startSpan(named: @autoclosure () -> String) -> BenchmarkSpan {
        NOPBenchmarkSpan.shared
    }
}

private final class NOPBenchmarkSpan: BenchmarkSpan {
    /// The no-op span shared instance.
    static let shared: BenchmarkSpan = NOPBenchmarkSpan()
    /// no-op
    func stop() {}
}
