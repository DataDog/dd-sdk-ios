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

        // When
        let context: DatadogContext = .mockWith(
            featuresAttributes: .mockSessionReplayAttributes(hasReplay: hasReplay)
        )

        // Then
        XCTAssertEqual(context.srBaggage?.isReplayBeingRecorded, hasReplay)
    }

    func testWhenSessionReplayIsNotConfigured_itReadsNoSRBaggage() {
        // When
        let context: DatadogContext = .mockWith(featuresAttributes: [:])

        // Then
        XCTAssertNil(context.srBaggage)
    }
}
