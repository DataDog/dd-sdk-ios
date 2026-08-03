/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
@testable import DatadogProfiling

// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
import DatadogMachProfiler.Pprof
// swiftlint:enable duplicate_imports

/// Pure-Swift fixture (allocated via swift_allocObject).
private final class IntegrationSwiftFixture { var payload = (0, 0, 0, 0) }
/// NSObject-rooted fixture (allocated via +allocWithZone:).
private final class IntegrationObjCFixture: NSObject { var payload = (0, 0, 0, 0) }

/// SQ6 exit criterion: one heap profile contains both an Obj-C class and a
/// pure-Swift class, correctly labelled, with no double-count.
final class SwiftAllocInterceptionIntegrationTests: XCTestCase {
    override func tearDown() {
        SwiftAllocInterception.stop()
        MemorySwizzlingPOC.stop()
        dd_memory_profiler_stop()
        super.tearDown()
    }

    func test_bothPathsEmitDistinctLabelledSamplesInOnePprof() throws {
        dd_memory_test_reset()
        dd_swift_alloc_test_reset()

        // Dual interception, one shared passive sampler.
        XCTAssertEqual(MemorySwizzlingPOC.start(), .ok)
        XCTAssertNotEqual(SwiftAllocInterception.start(), .failedNoSymbol)
        XCTAssertTrue(dd_memory_profiler_is_running())

        // Force each allocation to be sampled deterministically.
        dd_memory_test_force_next_sample()
        let objc = IntegrationObjCFixture()
        dd_memory_test_force_next_sample()
        let swiftObj = IntegrationSwiftFixture()

        try withExtendedLifetime(objc) {
            try withExtendedLifetime(swiftObj) {
                var snapshot = dd_memory_snapshot_capture()
                defer { dd_memory_snapshot_destroy(&snapshot) }
                XCTAssertGreaterThanOrEqual(snapshot.sample_count, 2,
                                            "both fixtures must be live-sampled")

                var out: UnsafeMutablePointer<UInt8>?
                let n = dd_memory_snapshot_to_pprof(&snapshot, "S", "V", "A", &out)
                defer { if let o = out { free(o) } }
                XCTAssertGreaterThan(n, 0)

                let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, n, out))
                defer { perftools__profiles__profile__free_unpacked(pprof, nil) }
                let strings = pprof.pointee.string_table!

                // Collect (class_name, source) label pairs across all samples.
                var pairs: [(String, String)] = []
                for si in 0..<Int(pprof.pointee.n_sample) {
                    guard let s = pprof.pointee.sample?[si] else { continue }
                    var byKey: [String: String] = [:]
                    for li in 0..<Int(s.pointee.n_label) {
                        guard let lbl = s.pointee.label?[li] else { continue }
                        let key = String(cString: strings[Int(lbl.pointee.key)]!)
                        if lbl.pointee.str != 0 {
                            byKey[key] = String(cString: strings[Int(lbl.pointee.str)]!)
                        }
                    }
                    if let cn = byKey["class_name"], let src = byKey["source"] {
                        pairs.append((cn, src))
                    }
                }

                let swiftHit = pairs.contains { $0.0.contains("IntegrationSwiftFixture") && $0.1 == "swift" }
                let objcHit  = pairs.contains { $0.0.contains("IntegrationObjCFixture") && $0.1 == "objc" }
                XCTAssertTrue(swiftHit, "missing pure-Swift sample with source=swift; got \(pairs)")
                XCTAssertTrue(objcHit, "missing Obj-C sample with source=objc; got \(pairs)")

                // No double-count: the two fixtures are distinct samples.
                let distinct = Set(pairs.map { "\($0.0)|\($0.1)" })
                    .filter { $0.contains("IntegrationSwiftFixture") || $0.contains("IntegrationObjCFixture") }
                XCTAssertEqual(distinct.count, 2)

                // 4 Go-aligned value types preserved.
                XCTAssertEqual(pprof.pointee.n_sample_type, 4)
            }
        }
    }
}
#endif
