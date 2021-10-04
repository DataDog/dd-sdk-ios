/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventBuilderTests: XCTestCase {
    func testGivenEventBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                viewEventMapper: { viewEvent in
                    return RUMViewEvent.mockRandom()
                }
            )
        )
        let originalEventModel = RUMViewEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.createRUMEvent(with: RUMViewEvent.mockRandom())
        )
        XCTAssertNotEqual(event.model, originalEventModel)
    }

    func testGivenEventBuilderWithEventMapper_whenEventIsDropped_itBuildsNoEvent() {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: { event in
                    return nil
                }
            )
        )
        let event = builder.createRUMEvent(with: RUMResourceEvent.mockRandom())
        XCTAssertNil(event)
    }

    func testGivenEventBuilderWithNoEventMapper_whenBuildingAnEvent_itBuildsEventWithOriginalModel() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: { event in
                    return event
                }
            )
        )
        let originalEventModel = RUMResourceEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.createRUMEvent(with: originalEventModel)
        )
        XCTAssertEqual(event.model, originalEventModel)
    }
}
