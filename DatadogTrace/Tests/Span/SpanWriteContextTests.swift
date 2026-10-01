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
    private struct OtherFeatureContext: AdditionalContext {
        static let key = "other-feature"
        let value: String
    }

    private let featureScope = FeatureScopeMock()

    @MainActor
    func testWhenRequestingSpanWriteContext_itProvidesInitialCoreContext() {
        let retrieveContext = expectation(description: "provide core context")

        var initialContext: DatadogContext = .mockRandom()
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext

        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        featureScope.contextMock = .mockRandom()

        writer.spanWriteContext { providedContext, _ in
            // Then
            DDAssertReflectionEqual(providedContext, initialContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
    }

    @MainActor
    func testWhenRemovingRUMContext_itPreservesOtherInitialContext() {
        let retrieveContext = expectation(description: "provide context without RUM ownership")
        var expectedContext: DatadogContext = .mockRandom()
        expectedContext.set(additionalContext: OtherFeatureContext(value: "initial"))
        var initialContext = expectedContext
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext
        let writer = LazySpanWriteContext(featureScope: featureScope, rumContextOverride: .remove)
        let currentContext: DatadogContext = .mockRandom()
        featureScope.contextMock = currentContext

        writer.spanWriteContext { providedContext, _ in
            XCTAssertNil(providedContext.additionalContext(ofType: RUMCoreContext.self))
            DDAssertReflectionEqual(providedContext, expectedContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        DDAssertReflectionEqual(featureScope.contextMock, currentContext)
    }

    @MainActor
    func testWhenReplacingRUMContext_itPreservesOtherInitialContext() {
        let retrieveContext = expectation(description: "provide context with request-time RUM ownership")
        let requestRUMContext: RUMCoreContext = .mockRandom()
        var expectedContext: DatadogContext = .mockRandom()
        expectedContext.set(additionalContext: OtherFeatureContext(value: "initial"))
        expectedContext.set(additionalContext: requestRUMContext)
        var initialContext = expectedContext
        initialContext.set(additionalContext: RUMCoreContext.mockRandom())
        featureScope.contextMock = initialContext
        let writer = LazySpanWriteContext(featureScope: featureScope, rumContextOverride: .replace(requestRUMContext))
        let currentContext: DatadogContext = .mockRandom()
        featureScope.contextMock = currentContext

        writer.spanWriteContext { providedContext, _ in
            XCTAssertEqual(providedContext.additionalContext(ofType: RUMCoreContext.self), requestRUMContext)
            DDAssertReflectionEqual(providedContext, expectedContext)
            retrieveContext.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        DDAssertReflectionEqual(featureScope.contextMock, currentContext)
    }

    func testWhenWritingEvent_itDoesNotBypassConsent() {
        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        writer.spanWriteContext { _, writer in
            writer.write(value: SpanEvent.mockAny())
        }

        // Then
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: false).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: true).count, 0)
    }
}
