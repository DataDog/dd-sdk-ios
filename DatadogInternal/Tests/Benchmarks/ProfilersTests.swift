/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class ProfilersTests: XCTestCase {
    private let recursiveCalls = 100
    private let allocationsCount = 100

    // MARK: - Slow

    func testSlow_IfCorrect() {
        let profiler = SlowSingleThreadProfiler()
        let root = profiler.startRootSpan(named: "root")
            let c1 = profiler.startChildSpan(named: "c1")
                let c11 = profiler.startChildSpan(named: "c11")
                c11.finish()
                let c12 = profiler.startChildSpan(named: "c12")
                    let c121 = profiler.startChildSpan(named: "c121")
                    c121.finish()
                c12.finish()
            c1.finish()
            let c2 = profiler.startChildSpan(named: "c2")
                let c21 = profiler.startChildSpan(named: "c21")
                c21.finish()
                let c22 = profiler.startChildSpan(named: "c22", childOf: c2)
                c22.finish()
            c2.finish()
        root.finish()

        XCTAssertEqual(
            dumpFinishedSpans(finishedSpans: profiler.finishedSpans, baseTime: .now()),
            """
            [#root]
               [#c1]
                  [#c11]
                  [#c12]
                     [#c121]
               [#c2]
                  [#c21]
                  [#c22]
            """
        )
    }

    func testSlow_HowFast() {
        guard #available(iOS 13.0, *) else {
            return
        }

        let profiler = SlowSingleThreadProfiler()
        func recursive(count: Int) {
            guard count > 0 else {
                return
            }
            let span = profiler.startChildSpan(named: "child-\(count)")
            recursive(count: count - 1)
            span.finish()
        }

        let start = Date()
        let root = profiler.startRootSpan(named: "root")
        recursive(count: recursiveCalls)
        root.finish()
        let stop = Date()

        print("⏱️🐌 Slow # How fast is profiler? - \(stop.timeIntervalSince(start).toMs)    (\(recursiveCalls) recursive calls)")
    }

    func testSlow_HowFastIsAllocation() {
        guard #available(iOS 13.0, *) else {
            return
        }
        let profiler = SlowSingleThreadProfiler()

        let start = Date()
        _ = profiler.startRootSpan(named: "root")
        for _ in (0..<allocationsCount) {
            _ = profiler.startChildSpan(named: "child")
        }
        let stop = Date()

        print("⏱️🐌 Slow # How fast is allocation? - \(stop.timeIntervalSince(start).toMs)    (\(allocationsCount) allocations)")
    }

    // MARK: - Fast

    func testFast_IfCorrect() {
        let profiler = FastTimeProfiler()
        let root = profiler.startSpan(named: "root")
            let c1 = profiler.startSpan(named: "c1")
                let c11 = profiler.startSpan(named: "c11")
                c11.finish()
                let c12 = profiler.startSpan(named: "c12")
                    let c121 = profiler.startSpan(named: "c121")
                    c121.finish()
                c12.finish()
            c1.finish()
            let c2 = profiler.startSpan(named: "c2")
                let c21 = profiler.startSpan(named: "c21")
                c21.finish()
                let c22 = profiler.startSpan(named: "c22")
                c22.finish()
            c2.finish()
        root.finish()

        XCTAssertEqual(
            dumpFinishedSpans(spansByID: profiler.spansByID, baseTime: .now()),
            """
            [#root]
               [#c1]
                  [#c11]
                  [#c12]
                     [#c121]
               [#c2]
                  [#c21]
                  [#c22]
            """
        )
    }

    func testFast_HowFast() {
        guard #available(iOS 13.0, *) else {
            return
        }

        let profiler = FastTimeProfiler()
        func recursive(count: Int) {
            guard count > 0 else {
                return
            }
            let span = profiler.startSpan(named: "child-\(count)")
            recursive(count: count - 1)
            span.finish()
        }

        let start = Date()
        let root = profiler.startSpan(named: "root")
        recursive(count: recursiveCalls)
        root.finish()
        let stop = Date()

        print("⏱️🏎️ Fast # How fast is profiler? - \(stop.timeIntervalSince(start).toMs)     (\(recursiveCalls)) recursive calls")
    }

    func testFast_HowFastIsAllocation() {
        guard #available(iOS 13.0, *) else {
            return
        }
        let profiler = FastTimeProfiler()

        let start = Date()
        _ = profiler.startSpan(named: "root")
        for _ in (0..<allocationsCount) {
            _ = profiler.startSpan(named: "child")
        }
        let stop = Date()

        print("⏱️🏎️ Fast # How fast is allocation? - \(stop.timeIntervalSince(start).toMs)    (\(allocationsCount) allocations)")
    }

    // MARK: - Fastest

    func testFastest_IfCorrect() {
        let profiler = FastestTimeProfiler(spansCount: 10)
        profiler.startSpan(named: "root")
            profiler.startSpan(named: "c1")
                profiler.startSpan(named: "c11")
                profiler.finishActiveSpan()
                profiler.startSpan(named: "c12")
                    profiler.startSpan(named: "c121")
                    profiler.finishActiveSpan()
                profiler.finishActiveSpan()
            profiler.finishActiveSpan()
            profiler.startSpan(named: "c2")
                profiler.startSpan(named: "c21")
                profiler.finishActiveSpan()
                profiler.startSpan(named: "c22")
                profiler.finishActiveSpan()
            profiler.finishActiveSpan()
        profiler.finishActiveSpan()

        XCTAssertEqual(
            dumpFinishedSpans(finishedSpans: profiler.spans, baseTime: .now()),
            """
            [#root]
               [#c1]
                  [#c11]
                  [#c12]
                     [#c121]
               [#c2]
                  [#c21]
                  [#c22]
            """
        )
    }

    func testFastest_HowFast() {
        guard #available(iOS 13.0, *) else {
            return
        }

        let profiler = FastestTimeProfiler(spansCount: recursiveCalls * 2)
        func recursive(count: Int) {
            guard count > 0 else {
                return
            }
            profiler.startSpan(named: #function)
            recursive(count: count - 1)
            profiler.finishActiveSpan()
        }

        let start = Date()
        profiler.startSpan(named: "root")
        recursive(count: recursiveCalls)
        profiler.finishActiveSpan()
        let stop = Date()

        print("⏱️⚡️ Fastest # How fast is profiler? - \(stop.timeIntervalSince(start).toMs)     (\(recursiveCalls)) recursive calls")
    }

    func testFastest_HowFastIsAllocation() {
        guard #available(iOS 13.0, *) else {
            return
        }
        let profiler = FastestTimeProfiler(spansCount: allocationsCount * 2)

        let start = Date()
        profiler.startSpan(named: "root")
        for _ in (0..<allocationsCount) {
            profiler.startSpan(named: "child")
        }
        let stop = Date()

        print("⏱️⚡️ Fastest # How fast is allocation? - \(stop.timeIntervalSince(start).toMs)    (\(allocationsCount) allocations)")
    }
}

private extension TimeInterval {
    var toMs: String {
        let value = (self * Double(1_000) * Double(100)).rounded() / Double(100)
        return "\(value)ms"
    }
}
