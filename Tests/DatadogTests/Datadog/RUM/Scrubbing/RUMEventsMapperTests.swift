/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventsMapperTests: XCTestCase {
    func testGivenMappersEnabled_whenModifyingEvents_itReturnsTheirNewRepresentation() throws {
        let originalViewEvent: RUMViewEvent = .mockRandom()
        let modifiedViewEvent: RUMViewEvent = .mockRandom()

        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let modifiedErrorEvent: RUMErrorEvent = .mockRandom()

        let originalCrashEvent: RUMCrashEvent = .mockRandom(error: originalErrorEvent)

        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let modifiedResourceEvent: RUMResourceEvent = .mockRandom()

        let originalActionEvent: RUMActionEvent = .mockRandom()
        let modifiedActionEvent: RUMActionEvent = .mockRandom()

        let originalLongTaskEvent: RUMLongTaskEvent = .mockRandom()
        let modifiedLongTaskEvent: RUMLongTaskEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: SyncRUMViewEventMapper({ viewEvent in
                XCTAssertEqual(viewEvent, originalViewEvent, "Mapper should be called with the original event.")
                return modifiedViewEvent
            }),
            errorEventMapper: SyncRUMErrorEventMapper({ errorEvent in
                XCTAssertEqual(errorEvent, originalErrorEvent, "Mapper should be called with the original event.")
                return modifiedErrorEvent
            }),
            resourceEventMapper: SyncRUMResourceEventMapper({ resourceEvent in
                XCTAssertEqual(resourceEvent, originalResourceEvent, "Mapper should be called with the original event.")
                return modifiedResourceEvent
            }),
            actionEventMapper: SyncRUMActionEventMapper({ actionEvent in
                XCTAssertEqual(actionEvent, originalActionEvent, "Mapper should be called with the original event.")
                return modifiedActionEvent
            }),
            longTaskEventMapper: SyncRUMLongTaskEventMapper({ longTaskEvent in
                XCTAssertEqual(longTaskEvent, originalLongTaskEvent, "Mapper should be called with the original event.")
                return modifiedLongTaskEvent
            })
        )

        // When
        let viewEventExpectation = XCTestExpectation(description: "View Event Mapper Callback called")
        var mappedViewEvent: RUMViewEvent?
        mapper.map(event: originalViewEvent) { event in
            mappedViewEvent = event
            viewEventExpectation.fulfill()
        }

        let errorEventExpectation = XCTestExpectation(description: "Error Event Mapper Callback called")
        var mappedErrorEvent: RUMErrorEvent?
        mapper.map(event: originalErrorEvent) { event in
            mappedErrorEvent = event
            errorEventExpectation.fulfill()
        }

        let crashEventExpectation = XCTestExpectation(description: "Crash Event Mapper Callback called")
        var mappedCrashEvent: RUMCrashEvent?
        mapper.map(event: originalCrashEvent) { event in
            mappedCrashEvent = event
            crashEventExpectation.fulfill()
        }

        let resourceEventExpectation = XCTestExpectation(description: "Resource Event Mapper Callback called")
        var mappedResourceEvent: RUMResourceEvent?
        mapper.map(event: originalResourceEvent) { event in
            mappedResourceEvent = event
            resourceEventExpectation.fulfill()
        }

        let actionEventExpectation = XCTestExpectation(description: "Action Event Mapper Callback called")
        var mappedActionEvent: RUMActionEvent?
        mapper.map(event: originalActionEvent) { event in
            mappedActionEvent = event
            actionEventExpectation.fulfill()
        }

        let longTaskEventExpectation = XCTestExpectation(description: "Long Task Event Mapper Callback called")
        var mappedLongTaskEvent: RUMLongTaskEvent?
        mapper.map(event: originalLongTaskEvent) { event in
            mappedLongTaskEvent = event
            longTaskEventExpectation.fulfill()
        }

        wait(for: [
            viewEventExpectation,
            errorEventExpectation,
            crashEventExpectation,
            resourceEventExpectation,
            actionEventExpectation,
            longTaskEventExpectation
        ], timeout: 0.1)

        // Then
        XCTAssertEqual(try XCTUnwrap(mappedViewEvent), modifiedViewEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedErrorEvent), modifiedErrorEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedResourceEvent), modifiedResourceEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedActionEvent), modifiedActionEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedLongTaskEvent), modifiedLongTaskEvent, "Mapper should return modified event.")

        XCTAssertEqual(try XCTUnwrap(mappedCrashEvent?.model), modifiedErrorEvent, "Mapper should return modified event.")
        AssertDictionariesEqual(
            try XCTUnwrap(mappedCrashEvent?.additionalAttributes),
            originalCrashEvent.additionalAttributes ?? [:],
            "Mapper should return unmodified event attributes."
        )
    }

    func testGivenMappersEnabled_whenDroppingEvents_itReturnsNil() {
        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let originalCrashEvent: RUMCrashEvent = .mockRandom()
        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let originalActionEvent: RUMActionEvent = .mockRandom()
        let originalLongTaskEvent: RUMLongTaskEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: nil,
            errorEventMapper: SyncRUMErrorEventMapper({ errorEvent in
                XCTAssertTrue(errorEvent == originalErrorEvent || errorEvent == originalCrashEvent.model, "Mapper should be called with the original event.")
                return nil
            }),
            resourceEventMapper: SyncRUMResourceEventMapper({ resourceEvent in
                XCTAssertEqual(resourceEvent, originalResourceEvent, "Mapper should be called with the original event.")
                return nil
            }),
            actionEventMapper: SyncRUMActionEventMapper({ actionEvent in
                XCTAssertEqual(actionEvent, originalActionEvent, "Mapper should be called with the original event.")
                return nil
            }),
            longTaskEventMapper: SyncRUMLongTaskEventMapper({ longTaskEvent in
                XCTAssertEqual(longTaskEvent, originalLongTaskEvent, "Mapper should be called with the original event.")
                return nil
            })
        )

        // When
        let errorEventExpectation = XCTestExpectation(description: "Error Event Mapper Callback called")
        var mappedErrorEvent: RUMErrorEvent?
        mapper.map(event: originalErrorEvent) { event in
            mappedErrorEvent = event
            errorEventExpectation.fulfill()
        }

        let crashEventExpectation = XCTestExpectation(description: "Crash Event Mapper Callback called")
        var mappedCrashEvent: RUMCrashEvent?
        mapper.map(event: originalCrashEvent) { event in
            mappedCrashEvent = event
            crashEventExpectation.fulfill()
        }

        let resourceEventExpectation = XCTestExpectation(description: "Resource Event Mapper Callback called")
        var mappedResourceEvent: RUMResourceEvent?
        mapper.map(event: originalResourceEvent) { event in
            mappedResourceEvent = event
            resourceEventExpectation.fulfill()
        }

        let actionEventExpectation = XCTestExpectation(description: "Action Event Mapper Callback called")
        var mappedActionEvent: RUMActionEvent?
        mapper.map(event: originalActionEvent) { event in
            mappedActionEvent = event
            actionEventExpectation.fulfill()
        }

        let longTaskEventExpectation = XCTestExpectation(description: "Long Task Event Mapper Callback called")
        var mappedLongTaskEvent: RUMLongTaskEvent?
        mapper.map(event: originalLongTaskEvent) { event in
            mappedLongTaskEvent = event
            longTaskEventExpectation.fulfill()
        }

        wait(for: [
            errorEventExpectation,
            crashEventExpectation,
            resourceEventExpectation,
            actionEventExpectation,
            longTaskEventExpectation
        ], timeout: 0.1)

        // Then
        XCTAssertNil(mappedErrorEvent, "Mapper should return nil.")
        XCTAssertNil(mappedCrashEvent, "Mapper should return nil.")
        XCTAssertNil(mappedResourceEvent, "Mapper should return nil.")
        XCTAssertNil(mappedActionEvent, "Mapper should return nil.")
        XCTAssertNil(mappedLongTaskEvent, "Mapper should return nil.")
    }

    func testGivenMappersDisabled_whenMappingEvents_itReturnsTheirOriginalRepresentation() throws {
        let originalViewEvent: RUMViewEvent = .mockRandom()
        let originalCrashEvent: RUMCrashEvent = .mockRandom()
        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let originalActionEvent: RUMActionEvent = .mockRandom()
        let originalLongTaskEvent: RUMLongTaskEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: nil,
            errorEventMapper: nil,
            resourceEventMapper: nil,
            actionEventMapper: nil,
            longTaskEventMapper: nil
        )

        // When
        let viewEventExpectation = XCTestExpectation(description: "View Event Mapper Callback called")
        var mappedViewEvent: RUMViewEvent?
        mapper.map(event: originalViewEvent) { event in
            mappedViewEvent = event
            viewEventExpectation.fulfill()
        }

        let errorEventExpectation = XCTestExpectation(description: "Error Event Mapper Callback called")
        var mappedErrorEvent: RUMErrorEvent?
        mapper.map(event: originalErrorEvent) { event in
            mappedErrorEvent = event
            errorEventExpectation.fulfill()
        }

        let crashEventExpectation = XCTestExpectation(description: "Crash Event Mapper Callback called")
        var mappedCrashEvent: RUMCrashEvent?
        mapper.map(event: originalCrashEvent) { event in
            mappedCrashEvent = event
            crashEventExpectation.fulfill()
        }

        let resourceEventExpectation = XCTestExpectation(description: "Resource Event Mapper Callback called")
        var mappedResourceEvent: RUMResourceEvent?
        mapper.map(event: originalResourceEvent) { event in
            mappedResourceEvent = event
            resourceEventExpectation.fulfill()
        }

        let actionEventExpectation = XCTestExpectation(description: "Action Event Mapper Callback called")
        var mappedActionEvent: RUMActionEvent?
        mapper.map(event: originalActionEvent) { event in
            mappedActionEvent = event
            actionEventExpectation.fulfill()
        }

        let longTaskEventExpectation = XCTestExpectation(description: "Long Task Event Mapper Callback called")
        var mappedLongTaskEvent: RUMLongTaskEvent?
        mapper.map(event: originalLongTaskEvent) { event in
            mappedLongTaskEvent = event
            longTaskEventExpectation.fulfill()
        }

        wait(for: [
            viewEventExpectation,
            errorEventExpectation,
            crashEventExpectation,
            resourceEventExpectation,
            actionEventExpectation,
            longTaskEventExpectation
        ], timeout: 0.1)

        // Then
        XCTAssertEqual(try XCTUnwrap(mappedViewEvent), originalViewEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedErrorEvent), originalErrorEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedCrashEvent), originalCrashEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedResourceEvent), originalResourceEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedActionEvent), originalActionEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedLongTaskEvent), originalLongTaskEvent, "Mapper should return the original event.")
    }

    func testGivenUnrecognizedEvent_whenMapping_itReturnsItsOriginalImplementation() throws {
        // Given
        struct UnrecognizedEvent: Encodable {
            let value: String
        }

        let originalEvent = UnrecognizedEvent(value: .mockRandom())

        // When
        let mapper = RUMEventsMapper(
            viewEventMapper: nil,
            errorEventMapper: SyncRUMErrorEventMapper({ _ in nil }),
            resourceEventMapper: SyncRUMResourceEventMapper({ _ in nil }),
            actionEventMapper: SyncRUMActionEventMapper({ _ in nil }),
            longTaskEventMapper: SyncRUMLongTaskEventMapper({ _ in nil })
        )

        let callbackExpectation = XCTestExpectation(description: "Mapper callback called")
        var mappedEvent: UnrecognizedEvent?
        mapper.map(event: originalEvent) { event in
            mappedEvent = event
            callbackExpectation.fulfill()
        }

        wait(for: [callbackExpectation], timeout: 0.1)

        // Then
        XCTAssertEqual(try XCTUnwrap(mappedEvent).value, originalEvent.value)
    }
}
