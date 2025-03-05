/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if DD_BENCHMARK
/// The benchmark endpoint to collect data for benchmarking.
public var bench: (profiler: BenchmarkProfiler, meter: BenchmarkMeter) = (NOPBench(), NOPBench())
#else
/// The benchmark endpoint to collect data for benchmarking. This static variable can only
/// be mutated in the benchmark environment.
public let bench: (profiler: BenchmarkProfiler, meter: BenchmarkMeter) = (NOPBench(), NOPBench())
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
    /// 
    /// - Parameter operation: The tracer operation name. The parameter is an auto-closure
    /// to not intialise the value if the profiler is no-op.
    /// - Returns: The tracer instance.
    func tracer(operation: @autoclosure () -> String) -> BenchmarkTracer
}

/// The Benchmark Meter provides interfaces to collect data in a benchmark
/// environment.
///
/// During benchmarking, a concrete implementation of the meter will be
/// injected to collect data during execution of the SDK.
///
/// In production, the profiler is no-op and immutable.
public protocol BenchmarkMeter {
    /// Returns a `BenchmarkCounter` instance for a given metric name.
    ///
    /// The counter metric will sum up added values.
    ///
    /// - Parameter metric: The metric name.
    /// - Returns: The counter instance.
    func counter(metric: @autoclosure () -> String) -> BenchmarkCounter

    /// Returns a `BenchmarkGauge` instance for a given metric name.
    ///
    /// The gauge metric will keep the latest value.
    ///
    /// - Parameter metric: The metric name.
    /// - Returns: The gauge instance.
    func gauge(metric: @autoclosure () -> String) -> BenchmarkGauge
}

/// The Benchmark Tracer will create and start spans in a benchmark environment.
/// This tracer can be used to measure CPU Time of inner operation of the SDK.
/// In production, the Benchmark Tracer is no-op.
public protocol BenchmarkTracer {
    /// Creates and starts a span at the current time.
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

/// The Benchmark Counter is a counter metric aggregator.
///
/// This meter can be used to count measures of the SDK.
/// In production, the Benchmark Counter is no-op.
public protocol BenchmarkCounter {
    func add(value: Double, attributes: @autoclosure () -> [String: String])
}

extension BenchmarkCounter {
    /// Increment the counter.
    ///
    /// - parameters:
    ///     - by: Amount to increment by.
    public func increment<FloatingPoint>(by amount: FloatingPoint = 1, attributes: @autoclosure () -> [String: String] = [:]) where FloatingPoint: BinaryFloatingPoint {
        add(value: Double(amount), attributes: attributes())
    }

    /// Increment the counter.
    ///
    /// - parameters:
    ///     - by: Amount to increment by.
    public func increment<Integer>(by amount: Integer = 1, attributes: @autoclosure () -> [String: String] = [:]) where Integer: BinaryInteger {
        add(value: Double(amount), attributes: attributes())
    }
}

/// The Benchmark Gauge is a gauge metric aggregator.
///
/// This meter can be used to track measures of the SDK.
/// In production, the Benchmark Gauge is no-op.
public protocol BenchmarkGauge {
    func record(value: Double, attributes: @autoclosure () -> [String: String])
}

extension BenchmarkGauge {
    /// Record value.
    public func record<FloatingPoint>(_ value: FloatingPoint, attributes: @autoclosure () -> [String: String] = [:]) where FloatingPoint: BinaryFloatingPoint {
        record(value: Double(value), attributes: attributes())
    }

    /// Record value.
    public func record<Integer>(_ value: Integer, attributes: @autoclosure () -> [String: String] = [:]) where Integer: BinaryInteger {
        record(value: Double(value), attributes: attributes())
    }
}

private final class NOPBench: BenchmarkProfiler, BenchmarkTracer, BenchmarkSpan, BenchmarkMeter, BenchmarkCounter, BenchmarkGauge {
    /// no-op
    func tracer(operation: @autoclosure () -> String) -> BenchmarkTracer { self }
    /// no-op
    func counter(metric: @autoclosure () -> String) -> BenchmarkCounter { self }
    /// no-op
    func gauge(metric: @autoclosure () -> String) -> BenchmarkGauge { self }
    /// no-op
    func add(value: Double, attributes: @autoclosure () -> [String: String]) { }
    /// no-op
    func record(value: Double, attributes: @autoclosure () -> [String: String]) { }
    /// no-op
    func startSpan(named: @autoclosure () -> String) -> BenchmarkSpan { self }
    /// no-op
    func stop() {}
}
