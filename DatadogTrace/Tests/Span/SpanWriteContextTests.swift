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
    private let featureScope = FeatureScopeMock()

    func testWhenRequestingSpanWriteContext_itProvidesInitialCoreContext() async {
        let initialContext: DatadogContext = .mockRandom()
        featureScope.contextMock = initialContext

        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        featureScope.contextMock = .mockRandom()

        let result = await writer.spanWriteContext()

        // Then
        XCTAssertNotNil(result)
        if let (providedContext, _) = result {
            DDAssertReflectionEqual(providedContext, initialContext)
        }
    }

    func testWhenWritingEvent_itDoesNotBypassConsent() async {
        // Given
        let writer = LazySpanWriteContext(featureScope: featureScope)

        // When
        if let (_, eventWriter) = await writer.spanWriteContext() {
            await eventWriter.write(value: SpanEvent.mockAny())
        }

        // Then
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: false).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: SpanEvent.self, withBypassConsent: true).count, 0)
    }
}
