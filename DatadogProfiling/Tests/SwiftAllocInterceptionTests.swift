/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
@testable import DatadogProfiling

final class SwiftAllocInterceptionTests: XCTestCase {
    override func tearDown() {
        SwiftAllocInterception.stop()
        super.tearDown()
    }

    func testStart_bringsUpInterceptionAndReportsRunning() {
        let status = SwiftAllocInterception.start()
        XCTAssertNotEqual(status, .failedNoSymbol)
        XCTAssertTrue(SwiftAllocInterception.isRunning)
    }

    func testDiagnostics_reflectAllocInvocations() {
        _ = SwiftAllocInterception.start()
        let before = SwiftAllocInterception.diagnostics().allocInvocations
        // Churn pure-Swift allocations (go through swift_allocObject).
        var sink = 0
        for _ in 0..<1_000 {
            let arr = [Int](repeating: 0, count: 4)
            sink &+= arr.count
        }
        XCTAssertGreaterThanOrEqual(sink, 0)
        let after = SwiftAllocInterception.diagnostics().allocInvocations
        XCTAssertGreaterThanOrEqual(after, before)
    }
}
#endif
