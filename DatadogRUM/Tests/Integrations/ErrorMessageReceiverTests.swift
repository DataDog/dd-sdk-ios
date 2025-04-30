/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities

@testable import DatadogRUM

class ErrorMessageReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var receiver: ErrorMessageReceiver! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        receiver = ErrorMessageReceiver(
            featureScope: featureScope,
            monitor: Monitor(
                dependencies: .mockWith(featureScope: featureScope),
                dateProvider: SystemDateProvider()
            )
        )
    }

    override func tearDown() {
        receiver = nil
    }

    func testReceivePartialLogError() throws {
        // When
        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "logger",
                type: nil,
                stack: nil,
                attributes: [:],
                binaryImages: nil
            )
        )

        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last, "It should send error")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.source, .logger)
    }

    func testReceiveCompleteLogError() throws {
        // Given
        let mockAttribute: String = .mockRandom()
        let mockBinaryImage: BinaryImage = .mockRandom()
        let message: FeatureMessage = .payload(
            RUMErrorMessage(
                time: Date(),
                message: "message-test",
                source: "custom",
                type: "type-test",
                stack: "stack-test",
                attributes: [
                    "any-key": mockAttribute
                ],
                binaryImages: [mockBinaryImage]
            )
        )

        // When
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        let event: RUMErrorEvent = try XCTUnwrap(featureScope.eventsWritten().last, "It should send error")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.type, "type-test")
        XCTAssertEqual(event.error.stack, "stack-test")
        XCTAssertEqual(event.error.source, .custom)
        XCTAssertNotNil(event.error.binaryImages)
        XCTAssertEqual(event.error.binaryImages?.count, 1)
        if let image = event.error.binaryImages?.first {
            XCTAssertEqual(mockBinaryImage.libraryName, image.name)
            XCTAssertEqual(mockBinaryImage.uuid, image.uuid)
            XCTAssertEqual(mockBinaryImage.architecture, image.arch)
            XCTAssertEqual(mockBinaryImage.isSystemLibrary, image.isSystem)
            XCTAssertEqual(mockBinaryImage.loadAddress, image.loadAddress)
            XCTAssertEqual(mockBinaryImage.maxAddress, image.maxAddress)
        }

        XCTAssertEqual(event.context?.contextInfo["any-key"] as? String, mockAttribute)
    }
}
