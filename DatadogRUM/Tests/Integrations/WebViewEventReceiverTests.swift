/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

class WebViewEventReceiverTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private let mockCommandSubscriber = RUMCommandSubscriberMock()

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(
            context: .mockWith(
                serverTimeOffset: 123,
                featuresAttributes: [
                    "rum": [
                        "ids": [
                            RUMContextAttributes.IDs.applicationID: "123456",
                            RUMContextAttributes.IDs.sessionID: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f"
                        ]
                    ]
                ]
            ),
            messageReceiver: WebViewEventReceiver.mockAny()
        )
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testReceiveEvent() throws {
        // Given
        struct Event: Encodable {
            let test: String
        }

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Event"),
            messageReceiver: WebViewEventReceiver.mockAny()
        )

        // When
        let sent: [String: Any] = [
            "test": String.mockRandom()
        ]

        core.send(
            message: .custom(key: WebViewEventReceiver.MessageKeys.browserEvent, baggage: .init(sent))
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let received: AnyEncodable = try XCTUnwrap(core.events().last, "It should send event")
        DDAssertJSONEqual(received, AnyEncodable(sent))
    }

    func testWhenValidWebRUMEventPassed_itDecoratesAndPassesToCoreMessageBus() throws {
        let receiver = WebViewEventReceiver(
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: mockCommandSubscriber
        )

        let webRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 2]
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_823_292,
            "service": "shopist-web-ui",
            "session": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]

        let expectedWebRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 1]
            ],
            "application": ["id": "123456"],
            "date": 1_640_252_823_292 + 123.toInt64Milliseconds,
            "service": "shopist-web-ui",
            "session": ["id": "e9796469-c2a1-43d6-b0f6-65c47d33cf5f"],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]

        receiver.write(event: webRUMEvent, to: core)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        DDAssertDictionariesEqual(writtenJSON, expectedWebRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenValidWebRUMEventPassedWithoutRUMContext_itPassesToCoreMessageBus() throws {
        core.context.featuresAttributes = [:]

        let receiver = WebViewEventReceiver(
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: mockCommandSubscriber
        )

        let webRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 2]
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_823_292,
            "service": "shopist-web-ui",
            "session": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]

        receiver.write(event: webRUMEvent, to: core)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        DDAssertDictionariesEqual(writtenJSON, webRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenNativeSessionIsSampledOut_itPassesWebEventToWriter() throws {
        let receiver = WebViewEventReceiver(
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: mockCommandSubscriber
        )

        let webRUMEvent: JSON = [
            "new_key": "new_value",
            "type": "unknown"
        ]

        receiver.write(event: webRUMEvent, to: core)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        DDAssertDictionariesEqual(writtenJSON, webRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenUnknownWebRUMEventPassed_itPassesToCoreMessageBus() throws {
        let receiver = WebViewEventReceiver(
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: mockCommandSubscriber
        )

        let unknownWebRUMEvent: JSON = [
            "new_key": "new_value",
            "type": "unknown"
        ]

        receiver.write(event: unknownWebRUMEvent, to: core)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        DDAssertDictionariesEqual(writtenJSON, unknownWebRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }
}
