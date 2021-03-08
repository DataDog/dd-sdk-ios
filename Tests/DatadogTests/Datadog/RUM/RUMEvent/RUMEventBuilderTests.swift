/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventBuilderTests: XCTestCase {
    func testItBuildsRUMEvent() throws {
        let builder = RUMEventBuilder(userInfoProvider: .mockAny(), eventsMapper: .mockNoOp())
        let event = try XCTUnwrap(
            builder.createRUMEvent(
                with: RUMDataModelMock(attribute: "foo"),
                attributes: ["foo": "bar", "fizz": "buzz"]
            )
        )

        XCTAssertEqual(event.model.attribute, "foo")
        XCTAssertEqual((event.attributes as? [String: String])?["foo"], "bar")
        XCTAssertEqual((event.attributes as? [String: String])?["fizz"], "buzz")
    }

    func testGivenEventBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder = RUMEventBuilder(
            userInfoProvider: .mockAny(),
            eventsMapper: .mockWith(
                viewEventMapper: { viewEvent in
                    return RUMViewEvent.mockRandom()
                }
            )
        )
        let originalEventModel = RUMViewEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.createRUMEvent(
                with: RUMViewEvent.mockRandom(),
                attributes: ["foo": "bar", "fizz": "buzz"]
            )
        )
        XCTAssertNotEqual(event.model, originalEventModel)
    }

    func testGivenEventBuilderWithEventMapper_whenEventIsDropped_itBuildsNoEvent() {
        let builder = RUMEventBuilder(
            userInfoProvider: .mockAny(),
            eventsMapper: .mockWith(
                resourceEventMapper: { event in
                    return nil
                }
            )
        )
        let event = builder.createRUMEvent(
            with: RUMResourceEvent.mockRandom(),
            attributes: [:]
        )
        XCTAssertNil(event)
    }

    func testGivenEventBuilderWithNoEventMapper_whenBuildingAnEvent_itBuildsEventWithOriginalModel() throws {
        let builder = RUMEventBuilder(
            userInfoProvider: .mockAny(),
            eventsMapper: .mockWith(
                resourceEventMapper: { event in
                    return event
                }
            )
        )
        let originalEventModel = RUMResourceEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.createRUMEvent(
                with: originalEventModel,
                attributes: [:]
            )
        )
        XCTAssertEqual(event.model, originalEventModel)
    }
}
