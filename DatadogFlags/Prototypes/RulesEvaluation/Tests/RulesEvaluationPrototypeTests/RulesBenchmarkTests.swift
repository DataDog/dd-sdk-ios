/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import XCTest
@testable import RulesEvaluationPrototype

internal final class RulesBenchmarkTests: XCTestCase {
    func testReleaseBenchmark() throws {
        guard ProcessInfo.processInfo.environment["DD_FLAGS_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt in with DD_FLAGS_BENCHMARK=1 and swift test -c release.")
        }
        #if DEBUG
        throw XCTSkip("Performance samples require a release build.")
        #else
        let data = try FixtureSupport.data("ufc-config")
        let evaluator = RulesEvaluator(configuration: try RulesConfiguration.parse(data))
        let cases = try FixtureSupport.cases()
        let count = 20_000
        for flag in ["numeric_flag", "kill-switch", "comparator-operator-test", "json-config-flag"] {
            let workload = cases.filter { $0.flag == flag }
            XCTAssertFalse(workload.isEmpty)
            for test in workload {
                let result = test.evaluate(with: evaluator)
                XCTAssertEqual(result.value, test.result.value)
                XCTAssertEqual(result.reason, test.result.reason)
            }
            var checksum = 0
            for index in 0..<1_000 {
                checksum &+= workload[index % workload.count].evaluate(with: evaluator).reason.rawValue.utf8.count
            }
            var samples: [UInt64] = []
            samples.reserveCapacity(count)
            var mismatches = 0
            for index in 0..<count {
                let test = workload[index % workload.count]
                let start = DispatchTime.now().uptimeNanoseconds
                let result = test.evaluate(with: evaluator)
                let end = DispatchTime.now().uptimeNanoseconds
                checksum &+= result.reason.rawValue.utf8.count + (result.variant?.utf8.count ?? 0)
                if result.value != test.result.value || result.reason != test.result.reason || result.errorCode != test.result.errorCode {
                    mismatches += 1
                }
                samples.append(end - start)
            }
            XCTAssertGreaterThan(checksum, 0)
            XCTAssertEqual(mismatches, 0)
            try report("warm-evaluation:\(flag)", samples: samples, checksum: checksum)
        }

        var preparation: [UInt64] = []
        var preparationChecksum = 0
        for _ in 0..<200 {
            let start = DispatchTime.now().uptimeNanoseconds
            let configuration = try RulesConfiguration.parse(data)
            let end = DispatchTime.now().uptimeNanoseconds
            preparationChecksum &+= configuration.flags.count
            preparation.append(end - start)
        }
        try report("json-decode-and-prepare", samples: preparation, checksum: preparationChecksum)

        var clock: [UInt64] = []
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            let end = DispatchTime.now().uptimeNanoseconds
            clock.append(end - start)
        }
        try report("clock-pair-baseline", samples: clock, checksum: 0)
        #endif
    }

    private func report(_ name: String, samples: [UInt64], checksum: Int) throws {
        let sorted = samples.sorted()
        func percentile(_ fraction: Double) -> Double {
            Double(sorted[max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)]) / 1_000
        }
        let row: [String: Any] = [
            "benchmark": name, "unit": "microseconds", "samples": sorted.count,
            "p50": percentile(0.50), "p95": percentile(0.95), "p99": percentile(0.99), "checksum": checksum,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "scope": "Swift prototype only; no bridge or telemetry",
        ]
        let json = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
