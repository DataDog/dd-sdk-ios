/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogProfiler

func workload_2() {
    var sum = 0.0
    for i in 0..<25_000 {
        sum += sin(Double(i)) * cos(Double(i))
    }
}

func workload_1() {
    var sum = 0.0
    for i in 0..<50_000 {
        sum += sin(Double(i)) * cos(Double(i))
    }
    workload_2()
}

func workload() {
    var sum = 0.0
    for i in 0..<100_000 {
        sum += sin(Double(i)) * cos(Double(i))
    }
    workload_1()
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
