/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventsMapperTests: XCTestCase {
    func testGivenMappersEnabled_whenModifyingEvents_itReturnsTheirNewRepresentation() throws {
        let originalViewEvent: RUMViewEvent = .mockRandom()
        let modifiedViewEvent: RUMViewEvent = .mockRandom()

        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let modifiedErrorEvent: RUMErrorEvent = .mockRandom()

        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let modifiedResourceEvent: RUMResourceEvent = .mockRandom()

        let originalActionEvent: RUMActionEvent = .mockRandom()
        let modifiedActionEvent: RUMActionEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: { viewEvent in
                XCTAssertEqual(viewEvent, originalViewEvent, "Mapper should be called with the original event.")
                return modifiedViewEvent
            },
            errorEventMapper: { errorEvent in
                XCTAssertEqual(errorEvent, originalErrorEvent, "Mapper should be called with the original event.")
                return modifiedErrorEvent
            },
            resourceEventMapper: { resourceEvent in
                XCTAssertEqual(resourceEvent, originalResourceEvent, "Mapper should be called with the original event.")
                return modifiedResourceEvent
            },
            actionEventMapper: { actionEvent in
                XCTAssertEqual(actionEvent, originalActionEvent, "Mapper should be called with the original event.")
                return modifiedActionEvent
            }
        )

        // When
        let mappedViewEvent = mapper.map(event: RUMEvent<RUMViewEvent>.mockWith(model: originalViewEvent))?.model
        let mappedErrorEvent = mapper.map(event: RUMEvent<RUMErrorEvent>.mockWith(model: originalErrorEvent))?.model
        let mappedResourceEvent = mapper.map(event: RUMEvent<RUMResourceEvent>.mockWith(model: originalResourceEvent))?.model
        let mappedActionEvent = mapper.map(event: RUMEvent<RUMActionEvent>.mockWith(model: originalActionEvent))?.model

        // Then
        XCTAssertEqual(try XCTUnwrap(mappedViewEvent), modifiedViewEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedErrorEvent), modifiedErrorEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedResourceEvent), modifiedResourceEvent, "Mapper should return modified event.")
        XCTAssertEqual(try XCTUnwrap(mappedActionEvent), modifiedActionEvent, "Mapper should return modified event.")
    }

    func testGivenMappersEnabled_whenModifyingEvents_itDoesNotModifyCustomAttributes() throws {
        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: { _ in .mockRandom() },
            errorEventMapper: { _ in .mockRandom() },
            resourceEventMapper: { _ in .mockRandom() },
            actionEventMapper: { _ in .mockRandom() }
        )

        // When
        let rumEvent1: RUMEvent<RUMViewEvent> = .mockRandomWith(model: .mockRandom())
        let rumEvent2: RUMEvent<RUMErrorEvent> = .mockRandomWith(model: .mockRandom())
        let rumEvent3: RUMEvent<RUMResourceEvent> = .mockRandomWith(model: .mockRandom())
        let rumEvent4: RUMEvent<RUMActionEvent> = .mockRandomWith(model: .mockRandom())
        let mappedRUMEvent1 = try XCTUnwrap(mapper.map(event: rumEvent1))
        let mappedRUMEvent2 = try XCTUnwrap(mapper.map(event: rumEvent2))
        let mappedRUMEvent3 = try XCTUnwrap(mapper.map(event: rumEvent3))
        let mappedRUMEvent4 = try XCTUnwrap(mapper.map(event: rumEvent4))

        // Then
        XCTAssertEqual(rumEvent1.attributes as! [String: String], mappedRUMEvent1.attributes as! [String: String])
        XCTAssertEqual(rumEvent1.userInfoAttributes as! [String: String], mappedRUMEvent1.userInfoAttributes as! [String: String])

        XCTAssertEqual(rumEvent2.attributes as! [String: String], mappedRUMEvent2.attributes as! [String: String])
        XCTAssertEqual(rumEvent2.userInfoAttributes as! [String: String], mappedRUMEvent2.userInfoAttributes as! [String: String])

        XCTAssertEqual(rumEvent3.attributes as! [String: String], mappedRUMEvent3.attributes as! [String: String])
        XCTAssertEqual(rumEvent3.userInfoAttributes as! [String: String], mappedRUMEvent3.userInfoAttributes as! [String: String])

        XCTAssertEqual(rumEvent4.attributes as! [String: String], mappedRUMEvent4.attributes as! [String: String])
        XCTAssertEqual(rumEvent4.userInfoAttributes as! [String: String], mappedRUMEvent4.userInfoAttributes as! [String: String])
    }

    func testGivenMappersEnabled_whenDroppingEvents_itReturnsNil() {
        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let originalActionEvent: RUMActionEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: nil,
            errorEventMapper: { errorEvent in
                XCTAssertEqual(errorEvent, originalErrorEvent, "Mapper should be called with the original event.")
                return nil
            },
            resourceEventMapper: { resourceEvent in
                XCTAssertEqual(resourceEvent, originalResourceEvent, "Mapper should be called with the original event.")
                return nil
            },
            actionEventMapper: { actionEvent in
                XCTAssertEqual(actionEvent, originalActionEvent, "Mapper should be called with the original event.")
                return nil
            }
        )

        // When
        let mappedErrorEvent = mapper.map(event: RUMEvent<RUMErrorEvent>.mockWith(model: originalErrorEvent))?.model
        let mappedResourceEvent = mapper.map(event: RUMEvent<RUMResourceEvent>.mockWith(model: originalResourceEvent))?.model
        let mappedActionEvent = mapper.map(event: RUMEvent<RUMActionEvent>.mockWith(model: originalActionEvent))?.model

        // Then
        XCTAssertNil(mappedErrorEvent, "Mapper should return nil.")
        XCTAssertNil(mappedResourceEvent, "Mapper should return nil.")
        XCTAssertNil(mappedActionEvent, "Mapper should return nil.")
    }

    func testGivenMappersDisabled_whenMappingEvents_itReturnsTheirOriginalRepresentation() throws {
        let originalViewEvent: RUMViewEvent = .mockRandom()
        let originalErrorEvent: RUMErrorEvent = .mockRandom()
        let originalResourceEvent: RUMResourceEvent = .mockRandom()
        let originalActionEvent: RUMActionEvent = .mockRandom()

        // Given
        let mapper = RUMEventsMapper(
            viewEventMapper: nil,
            errorEventMapper: nil,
            resourceEventMapper: nil,
            actionEventMapper: nil
        )

        // When
        let mappedViewEvent = mapper.map(event: RUMEvent<RUMViewEvent>.mockWith(model: originalViewEvent))?.model
        let mappedErrorEvent = mapper.map(event: RUMEvent<RUMErrorEvent>.mockWith(model: originalErrorEvent))?.model
        let mappedResourceEvent = mapper.map(event: RUMEvent<RUMResourceEvent>.mockWith(model: originalResourceEvent))?.model
        let mappedActionEvent = mapper.map(event: RUMEvent<RUMActionEvent>.mockWith(model: originalActionEvent))?.model

        // Then
        XCTAssertEqual(try XCTUnwrap(mappedViewEvent), originalViewEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedErrorEvent), originalErrorEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedResourceEvent), originalResourceEvent, "Mapper should return the original event.")
        XCTAssertEqual(try XCTUnwrap(mappedActionEvent), originalActionEvent, "Mapper should return the original event.")
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
            errorEventMapper: { _ in nil },
            resourceEventMapper: { _ in nil },
            actionEventMapper: { _ in nil }
        )

        let mappedEvent = try XCTUnwrap(mapper.map(event: originalEvent))

        // Then
        XCTAssertEqual(mappedEvent.value, originalEvent.value)
    }
}
