/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogProfiler

// A workload that is CPU-intensive and has consistent execution time
func workload() {
    // Use a large enough number to make the workload meaningful
    let iterations = 1_000_000
    
    // Use volatile to prevent compiler optimizations
    var volatileSum: Double = 0.0
    var volatileCount: Int = 0
    
    // Mix of floating point and integer operations
    for i in 0..<iterations {
        // Floating point operations
        volatileSum += sin(Double(i)) * cos(Double(i))
        
        // Integer operations and branching
        if i % 2 == 0 {
            volatileCount += i
        } else {
            volatileCount -= i
        }
        
        // Prevent compiler from optimizing away the loop
        if volatileSum.isNaN {
            break
        }
    }
    
    // Use the results to prevent compiler optimizations
    _ = volatileSum + Double(volatileCount)
}

final class DatadogProfilerTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPerformanceBaseline() throws {
        self.measure(metrics: [XCTCPUMetric(), XCTMemoryMetric()]) {
            workload()
        }
    }

    func testPerformanceInstrument() throws {
        let profiler = MachProfiler(currentThreadOnly: true)
        self.measure(metrics: [XCTCPUMetric(), XCTMemoryMetric()]) {
            profiler.start()
            workload()
            profiler.stop()
        }
    }
}
