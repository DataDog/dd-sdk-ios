/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMEventBuilderTests: XCTestCase {
    func testGivenEventBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                viewEventMapper: { _ in .mockRandom() }
            )
        )
        let originalEventModel = RUMViewEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.build(from: originalEventModel)
        )

        DDAssertReflectionNotEqual(event, originalEventModel)
    }

    func testGivenEventBuilderWithEventMapper_whenEventIsDropped_itBuildsNoEvent() {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: { _ in nil }
            )
        )
        let event = builder.build(from: RUMResourceEvent.mockRandom())
        XCTAssertNil(event)
    }

    func testGivenEventBuilderWithNoEventMapper_whenBuildingAnEvent_itBuildsEventWithOriginalModel() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: { $0 }
            )
        )
        let originalEventModel = RUMResourceEvent.mockRandom()
        let event = try XCTUnwrap(
            builder.build(from: originalEventModel)
        )
        DDAssertReflectionEqual(event, originalEventModel)
    }
}
