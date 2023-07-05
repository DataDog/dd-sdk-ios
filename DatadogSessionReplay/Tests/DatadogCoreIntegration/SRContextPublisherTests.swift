/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
import TestUtilities

class SRContextPublisherTests: XCTestCase {
    func testItSetsHasReplayAccordingly() throws {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)

        srContextPublisher.setHasReplay(true)

        let hasReplay = try XCTUnwrap(core.hasReplay)
        XCTAssertTrue(hasReplay)
    }

    func testItSetsRecordsCountAccordingly() {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)

        let recordsCount: [String: Int64] = ["view-id": 2]
        srContextPublisher.setRecordsCount(recordsCount)

        XCTAssertEqual(core.recordsCount, recordsCount)
    }

    func testItDoesNotOverridePreviouslySetValue() throws {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)
        let recordsCount: [String: Int64] = ["view-id": 2]

        srContextPublisher.setHasReplay(true)
        srContextPublisher.setRecordsCount(recordsCount)

        XCTAssertEqual(core.recordsCount, recordsCount)
        let hasReplay = try XCTUnwrap(core.hasReplay)
        XCTAssertTrue(hasReplay)

        srContextPublisher.setHasReplay(false)

        let hasReplay2 = try XCTUnwrap(core.hasReplay)
        XCTAssertFalse(hasReplay2)
        XCTAssertEqual(core.recordsCount, recordsCount)
    }
}

fileprivate extension PassthroughCoreMock {
    var hasReplay: Bool? {
        return context.featuresAttributes["session-replay"]?.has_replay
    }

    var recordsCount: [String: Int64]? {
        return context.featuresAttributes["session-replay"]?.records_count
    }
}
