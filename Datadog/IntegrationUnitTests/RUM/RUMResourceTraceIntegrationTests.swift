/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogTrace

class RUMResourceTraceIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    /*
     1.  No active span, sampled, session sampled, request sampled.
     2.  No active span, sampled, session sampled, request not sampled.
     3.  No active span, sampled, session not sampled, request with high sample rate but not sampled due to session.
     4.  No active span, sampled, session not sampled, request with low sample rate.

     1a. No active span, not sampled, session sampled, request sampled.
     2a. No active span, not sampled, session sampled, request not sampled.
     3a. No active span, not sampled, session not sampled, request with high sample rate but not sampled due to session.
     4a. No active span, not sampled, session not sampled, request with low sample rate.

     5.  Active span, sampled, session sampled, request with high sample rate -> Sampled
     6.  Active span, sampled, session sampled, request with low sample rate -> sampled
     7.  Active span, sampled, session not sampled, request with high sample rate -> not sampled
     8.  Active span, sampled, session not sampled, request with low sample rate -> not sampled

     9.  Active span, not sampled, session sampled, request with high sample rate -> Sampled
     10. Active span, not sampled, session sampled, request with low sample rate -> not sampled
     11. Active span, not sampled, session not sampled, request with high sample rate -> not sampled
     12. Active span, not sampled, session not sampled, request with low sample rate -> not sampled
     */

    func testNoActiveSpan_sessionSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: true)
        
    }

    private func initTraceAndMakeSpan(active: Bool, sampled: Bool) -> OTSpan {
        Trace.enable(
            with: Trace.Configuration(sampleRate: sampled ? 100 : 0),
            in: core
        )

        let span = Tracer.shared(in: core).startRootSpan(operationName: "test-op")
        if active {
            span.setActive()
        }
        return span
    }



}
