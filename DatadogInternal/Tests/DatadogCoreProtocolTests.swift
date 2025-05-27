/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class DatadogCoreProtocolTests: XCTestCase {
    func testSendMessageExtension() {
        // Given
        let receiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)

        // When
        core.send(message: .payload("value"))

        // Then
        XCTAssertEqual(
            receiver.messages.last?.asPayload as? String, "value", "DatadogCoreProtocol.send(message:) should forward message"
        )
    }

    func testAdditionalContextExtension() throws {
        // Given
        let core = PassthroughCoreMock()

        struct MyContext: AdditionalContext, Equatable {
            static let key = "my-context"
            let value: String
        }

        // When
        core.set(context: MyContext(value: "value"))

        // Then
        XCTAssertEqual(core.context.additionalContext(ofType: MyContext.self), MyContext(value: "value"))

        // When
        core.removeContext(ofType: MyContext.self)

        // Then
        XCTAssertNil(core.context.additionalContext(ofType: MyContext.self))
    }
}
