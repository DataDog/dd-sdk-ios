/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventBuilderTests: XCTestCase {
    func testGivenEventBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                viewEventMapper: SyncRUMViewEventMapper({ viewEvent in
                    return RUMViewEvent.mockRandom()
                })
            )
        )
        let expectation = XCTestExpectation(description: "Mapper callback called.")
        let originalEventModel = RUMViewEvent.mockRandom()
        builder.build(from: RUMViewEvent.mockRandom()) { event in
            XCTAssertNotNil(event)
            XCTAssertNotEqual(event, originalEventModel)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testGivenEventBuilderWithEventMapper_whenEventIsDropped_itBuildsNoEvent() {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: SyncRUMResourceEventMapper({ event in
                    return nil
                })
            )
        )
        let expectation = XCTestExpectation(description: "Mapper callback called.")
        builder.build(from: RUMResourceEvent.mockRandom()) { event in
            XCTAssertNil(event)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testGivenEventBuilderWithNoEventMapper_whenBuildingAnEvent_itBuildsEventWithOriginalModel() throws {
        let builder = RUMEventBuilder(
            eventsMapper: .mockWith(
                resourceEventMapper: SyncRUMResourceEventMapper({ event in
                    return event
                })
            )
        )
        let expectation = XCTestExpectation(description: "Mapper callback called.")
        let originalEventModel = RUMResourceEvent.mockRandom()
        builder.build(from: originalEventModel) { event in
            XCTAssertNotNil(event)
            XCTAssertEqual(event, originalEventModel)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.1)
    }
}
