/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FirstPartyURLsFilterTests: XCTestCase {
    private let filter = FirstPartyURLsFilter(
        configuration: .mockWith(
            userDefinedFirstPartyHosts: ["first-party.com", "eu"]
        )
    )

    func testWhenURLHostEndingMatchesAnyUserDefinedHost_itIsConsideredFirstParty() {
        let fixtures = [
            "http://first-party.com/",
            "https://first-party.com/",
            "https://api.first-party.com/v2/users",
            "https://www.first-party.com/",
            "https://login:p4ssw0rd@first-party.com:999/",
            "http://any-domain.eu/",
            "https://any-domain.eu/",
            "https://api.any-domain.eu/v2/users",
            "https://www.any-domain.eu/",
            "https://login:p4ssw0rd@www.any-domain.eu:999/",
            "https://api.any-domain.org.eu/",
        ]

        fixtures.forEach { fixture in
            let url = URL(string: fixture)!
            XCTAssertTrue(
                filter.isFirstParty(url: url),
                "The url: `\(url)` should be matched as first party."
            )
        }
    }

    func testWhenURLHostDoesNotMatchEndingOfAnyOfUserDefinedHosts_itIsNotConsideredFirstParty() {
        let fixtures = [
            "http://third-party.com/",
            "https://third-party.com/",
            "https://api.third-party.com/v2/users",
            "https://www.third-party.com/",
            "https://login:p4ssw0rd@third-party.com:999/",
            "http://any-domain.org/",
            "https://any-domain.org/",
            "https://api.any-domain.org/v2/users",
            "https://www.any-domain.org/",
            "https://login:p4ssw0rd@www.any-domain.org:999/",
            "https://api.any-domain.eu.org/",
        ]

        fixtures.forEach { fixture in
            let url = URL(string: fixture)!
            XCTAssertFalse(
                filter.isFirstParty(url: url),
                "The url: `\(url)` should NOT be matched as first party."
            )
        }
    }
}
