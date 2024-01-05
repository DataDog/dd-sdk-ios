/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogTrace

class SpanWriteContextTests: XCTestCase {
    func testWhenRequestingSpanWriteContext_itProvidesInitialCoreContext() {
        let retrieveContext = expectation(description: "provide core context")
        let writeEvent = expectation(description: "write event to core")

        let initialContext: DatadogContext = .mockRandom()

        // Given
        let core = PassthroughCoreMock(context: initialContext, expectation: writeEvent)
        let writer = LazySpanWriteContext(core: core)

        // When
        core.context = .mockRandom()
        writer.spanWriteContext { providedContext, _ in
            // Then
            DDAssertReflectionEqual(providedContext, initialContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
    }

    func testWhenWritingEvent_itRespectsCoreConsentAndBatching() {
        let core = PassthroughCoreMock(
            expectation: expectation(description: "write event to core"),
            bypassConsentExpectation: invertedExpectation(description: "do not bypass consent"),
            forceNewBatchExpectation: invertedExpectation(description: "do not force new batch")
        )

        // Given
        let writer = LazySpanWriteContext(core: core)

        // When
        writer.spanWriteContext { _, writer in
            writer.write(value: SpanEvent.mockAny())
        }

        waitForExpectations(timeout: 0.5)
    }
}
