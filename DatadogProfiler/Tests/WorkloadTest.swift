/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogProfiler

struct WorkloadMetrics: CustomStringConvertible {
    let sortTime: UInt64
    let fibonacciTime: UInt64
    let primeTime: UInt64

    var description: String {
        """
        Sort: \(sortTime / 1_000_000)ms
        Fibonacci: \(fibonacciTime / 1_000_000)ms
        Prime: \(primeTime / 1_000_000)ms
        """
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            sortTime: lhs.sortTime + rhs.sortTime,
            fibonacciTime: lhs.fibonacciTime + rhs.fibonacciTime,
            primeTime: lhs.primeTime + rhs.primeTime
        )
    }

    static func / (lhs: Self, rhs: UInt64) -> Self {
        Self(
            sortTime: lhs.sortTime / rhs,
            fibonacciTime: lhs.fibonacciTime / rhs,
            primeTime: lhs.primeTime / rhs
        )
    }
}


// A workload that is CPU-intensive and has consistent execution time
private func workload() -> WorkloadMetrics {
    // Generate random numbers
    var numbers = (0..<10000).map { _ in Int.random(in: 0..<1000) }

    // Sort the list multiple times
    let sortTime = measureTime {
        for _ in 0..<5 {
            numbers.sort()
            numbers.reverse()
        }
    }

    // Calculate Fibonacci numbers
    let fibonacciTime = measureTime {
        var fibs: [Int] = []
        for i in 0..<25 {
            fibs.append(fibonacci(i))
        }
        _ = fibs.reduce(0, +) // Use result to prevent optimization
    }

    // Check for prime numbers
    let primeTime = measureTime {
        var primes: [Int] = []
        for num in numbers {
            if isPrime(num) {
                primes.append(num)
            }
        }
        _ = primes.reduce(0, +) // Use result to prevent optimization
    }

    return WorkloadMetrics(
        sortTime: sortTime,
        fibonacciTime: fibonacciTime,
        primeTime: primeTime
    )
}

// Fibonacci calculation
func fibonacci(_ n: Int) -> Int {
    if n <= 1 {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

// Prime number check
func isPrime(_ num: Int) -> Bool {
    if num <= 1 {
        return false
    }
    for i in 2..<num {
        if num % i == 0 {
            return false
        }
    }
    return true
}

func measureTime(_ block: () -> Void) -> UInt64 {
    var start = timespec()
    var end = timespec()

    clock_gettime(CLOCK_MONOTONIC_RAW, &start)
    block()
    clock_gettime(CLOCK_MONOTONIC_RAW, &end)

    // Convert to nanoseconds
    let startNs = UInt64(start.tv_sec) * 1_000_000_000 + UInt64(start.tv_nsec)
    let endNs = UInt64(end.tv_sec) * 1_000_000_000 + UInt64(end.tv_nsec)
    return endNs - startNs
}

struct PerformanceDataWriter {
    let url: URL

    init(url: URL) {
        self.url = url
        try? FileManager.default.removeItem(at: url)
    }

    init() {
        self.init(
            url: FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("perf.csv")
        )
    }

    func write(run: String, timings: [UInt64], metrics: [WorkloadMetrics]) throws {
        let line = "\n\(run),\(timings.count),\"\(timings)\",\"\(metrics.map { $0.sortTime })\",\"\(metrics.map { $0.fibonacciTime })\",\"\(metrics.map { $0.primeTime })\""
        if let file = FileHandle(forWritingAtPath: url.path) {
            defer { file.closeFile() }
            file.seekToEndOfFile()
            file.write(line.data(using: .utf8)!)
         } else {
            let header = "run,count,timings,sort_times,fibonacci_times,prime_times"
            try "\(header)\(line)".data(using: .utf8)!.write(to: url, options: .atomic)
         }
    }
}

class WorkloadThread: Thread {
    private let iterations: Int
    private let isProfiling: Bool
    private let writer: PerformanceDataWriter
    private let expectation: XCTestExpectation?

    init(
        isProfiling: Bool,
        writer: PerformanceDataWriter,
        iterations: Int = 1_000,
        expectation: XCTestExpectation? = nil
    ) {
        self.iterations = iterations
        self.isProfiling = isProfiling
        self.writer = writer
        self.expectation = expectation
        super.init()
    }

    override func main() {
        print("Run workload thread...")

        if isProfiling {
            print("...with profiling")
            Profiler.start(currentThreadOnly: true)
        }

        var totalMetrics = WorkloadMetrics(sortTime: 0, fibonacciTime: 0, primeTime: 0)
        var allMetrics: [WorkloadMetrics] = []
        let timings = (0..<iterations).map { _ in
            defer { Thread.sleep(forTimeInterval: 0.008) }
            
            let metrics = workload()
            allMetrics.append(metrics)
            totalMetrics = totalMetrics + metrics
            return metrics.sortTime + metrics.fibonacciTime + metrics.primeTime
        }

        if isProfiling {
            Profiler.stop()
        }

        // Print average metrics
        print("\nAverage metrics per iteration:")
        print(totalMetrics / UInt64(iterations))

        print("\nWriting data to: \(writer.url.path)")
        try! writer.write(
            run: isProfiling ? "profiling" : "baseline",
            timings: timings,
            metrics: allMetrics
        )

        expectation?.fulfill()
    }
}


class WorkloadTest: XCTestCase {
    let writer = PerformanceDataWriter()

    func test() {
        let baseline = expectation(description: "Baseline Run")
        WorkloadThread(isProfiling: false, writer: writer, expectation: baseline).start()
        wait(for: [baseline], timeout: 300)

        let profiling = expectation(description: "Profiling Run")
        WorkloadThread(isProfiling: true, writer: writer, expectation: profiling).start()
        wait(for: [profiling], timeout: 300)
    }
}
