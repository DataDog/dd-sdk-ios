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

        let recordsCountByViewID: [String: Int64] = ["view-id": 2]
        srContextPublisher.setRecordsCountByViewID(recordsCountByViewID)

        XCTAssertEqual(core.recordsCountByViewID, recordsCountByViewID)
    }

    func testItDoesNotOverridePreviouslySetValue() throws {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)
        let recordsCountByViewID: [String: Int64] = ["view-id": 2]

        srContextPublisher.setHasReplay(true)
        srContextPublisher.setRecordsCountByViewID(recordsCountByViewID)

        XCTAssertEqual(core.recordsCountByViewID, recordsCountByViewID)
        let hasReplay = try XCTUnwrap(core.hasReplay)
        XCTAssertTrue(hasReplay)

        srContextPublisher.setHasReplay(false)

        let hasReplay2 = try XCTUnwrap(core.hasReplay)
        XCTAssertFalse(hasReplay2)
        XCTAssertEqual(core.recordsCountByViewID, recordsCountByViewID)
    }
}

private extension PassthroughCoreMock {
    var hasReplay: Bool? { try? context.baggages["sr_has_replay"]?.decode() }

    var recordsCountByViewID: [String: Int64]? {
        try? context.baggages["sr_records_count_by_view_id"]?.decode()
    }
}
