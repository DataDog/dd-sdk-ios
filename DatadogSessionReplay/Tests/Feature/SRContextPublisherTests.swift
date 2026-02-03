/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogSessionReplay

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
    var hasReplay: Bool? {
        context.additionalContext(
            ofType: SessionReplayCoreContext.HasReplay.self
        )?.value
    }

    var recordsCountByViewID: [String: Int64]? {
        context.additionalContext(
            ofType: SessionReplayCoreContext.RecordsCount.self
        )?.value
    }
}
#endif
