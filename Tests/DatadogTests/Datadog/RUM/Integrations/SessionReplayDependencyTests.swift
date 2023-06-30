/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SessionReplayDependencyTests: XCTestCase {
    func testWhenSessionReplayIsConfigured_itReadsReplayBeingRecorded() {
        let hasReplay: Bool = .random()
        let recordsCount: [String: Int64] = [.mockRandom(): .mockRandom()]

        // When
        let context: DatadogContext = .mockWith(
            featuresAttributes: .mockSessionReplayAttributes(hasReplay: hasReplay, recordsCount: recordsCount)
        )

        // Then
        XCTAssertEqual(context.srBaggage?.isReplayBeingRecorded, hasReplay)
        XCTAssertEqual(context.srBaggage?.recordsCount, recordsCount)
    }

    func testWhenSessionReplayIsNotConfigured_itReadsNoSRBaggage() {
        // When
        let context: DatadogContext = .mockWith(featuresAttributes: [:])

        // Then
        XCTAssertNil(context.srBaggage)
    }
}
