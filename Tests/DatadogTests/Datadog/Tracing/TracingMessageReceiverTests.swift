/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class TracingMessageReceiverTests: XCTestCase {
    func testItReceivesRUMContext() throws {
        let core = DatadogCoreProxy(
            context: .mockWith(featuresAttributes: ["rum": ["key": "value1"]])
        )
        defer { core.flushAndTearDown() }

        // Given
        let receiver = TracingMessageReceiver()
        try core.register(feature: DatadogFeatureMock(messageReceiver: receiver))
        XCTAssertNil(receiver.rum.attribues, "RUM context should be nil until it is set by RUM")

        // When
        core.set(feature: "rum", attributes: { ["key": "value2"] })

        // Then
        core.flush()
        XCTAssertEqual(receiver.rum.attribues as? [String: String], ["key": "value2"])
    }
}
