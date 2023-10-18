/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

class SessionReplayDependencyTests: XCTestCase {
    func testWhenSessionReplayIsConfigured_itReadsReplayBeingRecorded() throws {
        let hasReplay: Bool = .random()
        let recordsCountByViewID: [String: Int64] = [.mockRandom(): .mockRandom()]

        // When
        let context: DatadogContext = .mockWith(
            baggages: try .mockSessionReplayAttributes(hasReplay: hasReplay, recordsCountByViewID: recordsCountByViewID)
        )

        // Then
        XCTAssertEqual(context.hasReplay, hasReplay)
        XCTAssertEqual(context.recordsCountByViewID, recordsCountByViewID)
    }

    func testWhenSessionReplayIsNotConfigured_itReadsNoSRBaggage() {
        // When
        let context: DatadogContext = .mockWith(baggages: [:])

        // Then
        XCTAssertNil(context.hasReplay)
        XCTAssert(context.recordsCountByViewID.isEmpty)
    }
}
