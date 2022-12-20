/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class InternalURLsFilterTests: XCTestCase {
    private let filter = InternalURLsFilter(
        urls: [
            "https://dd.internal.com/logs",
            "https://dd.internal.com/traces",
            "https://dd.internal.com/rum"
        ]
    )

    func testWhenURLBeginningMatchesAnySDKInternalURL_itIsConsideredInternal() {
        let fixtures = [
            "https://dd.internal.com/logs",
            "https://dd.internal.com/logs/v2/endpoint?q=123",
            "https://dd.internal.com/traces",
            "https://dd.internal.com/traces/v2/endpoint?q=123",
            "https://dd.internal.com/rum",
            "https://dd.internal.com/rum/v2/endpoint?q=123",
        ]

        fixtures.forEach { fixture in
            let url = URL(string: fixture)!
            XCTAssertTrue(
                filter.isInternal(url: url),
                "The url: `\(url)` should be matched as internal."
            )
        }
    }

    func testWhenURLBeginningDoesNotMatchAnyOfSDKInternalURLs_itIsNotConsideredInternal() {
        let fixtures = [
            "http://dd.internal.com/logs",
            "http://dd.internal.com/logs/v2/endpoint?q=123",
            "http://dd.internal.com/traces",
            "http://dd.internal.com/traces/v2/endpoint?q=123",
            "http://dd.internal.com/rum",
            "http://dd.internal.com/rum/v2/endpoint?q=123",
            "https://any-domain.com/",
            "https://api.any-domain.com/v2/users",
        ]

        fixtures.forEach { fixture in
            let url = URL(string: fixture)!
            XCTAssertFalse(
                filter.isInternal(url: url),
                "The url: `\(url)` should NOT be matched as internal."
            )
        }
    }
}
