/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class TracingMessageReceiverTests: XCTestCase {
    func testReceiveRUMContext() throws {
        // Given
        let core = PassthroughCoreMock(
            messageReceiver: TracingMessageReceiver()
        )

        let integration = TracingWithRUMIntegration()
        Global.sharedTracer = Tracer.mockWith(
            core: core,
            rumIntegration: integration
        )
        defer { Global.sharedTracer = DDNoopTracer() }

        // When
        core.context = .mockWith(featuresAttributes: [
            "rum": ["key": "value"]
        ])

        // Then
        let value = try XCTUnwrap(integration.attribues?["key"] as? String)
        XCTAssertEqual(value, "value")
    }
}
