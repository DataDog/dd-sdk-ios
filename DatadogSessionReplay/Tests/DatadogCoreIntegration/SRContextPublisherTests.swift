/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
import TestUtilities

class SRContextPublisherTests: XCTestCase {
    func testItSetsHasReplayAccordingly() {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)

        srContextPublisher.setRecordingIsPending(true)

        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, true)
    }

    func testItSetsRecordsCountAccordingly() {
        let core = PassthroughCoreMock()
        let srContextPublisher = SRContextPublisher(core: core)

        let recordsCount: [String: Int64]  = ["view-id": 2]
        srContextPublisher.setRecordsCount(recordsCount)

        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["records_count"] as? [String: Int64], recordsCount)
    }
}
