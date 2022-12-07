/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FirstPartyHostsTests: XCTestCase {
    let hostsDictionary: [String: Set<TracingHeaderType>] = [
        "http://first-party.com/": .init(arrayLiteral: .w3c, .b3s),
        "https://first-party.com/": .init(arrayLiteral: .w3c, .b3s),
        "https://api.first-party.com/v2/users": .init(arrayLiteral: .w3c, .b3s),
        "https://www.first-party.com/": .init(arrayLiteral: .w3c, .b3s),
        "https://login:p4ssw0rd@first-party.com:999/": .init(arrayLiteral: .w3c, .b3s),
        "http://any-domain.eu/": .init(arrayLiteral: .w3c, .b3s),
        "https://any-domain.eu/": .init(arrayLiteral: .w3c, .b3s),
        "https://api.any-domain.eu/v2/users": .init(arrayLiteral: .w3c, .b3s),
        "https://www.any-domain.eu/": .init(arrayLiteral: .w3c, .b3s),
        "https://login:p4ssw0rd@www.any-domain.eu:999/": .init(arrayLiteral: .w3c, .b3s),
        "https://api.any-domain.org.eu/": .init(arrayLiteral: .w3c, .b3s),
    ]

    let otherHosts = [
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

    func testGivenEmptyDictionary_itReturnsDefaultTracingHeaderTypes() {
        let headerTypesProvider = FirstPartyHosts()
        (hostsDictionary.keys + otherHosts).forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init())
        }
        XCTAssertTrue(headerTypesProvider.hosts.isEmpty)
    }

    func testGivenEmptyTracingHeaderTypes_itReturnsNoTracingHeaderTypes() {
        let headerTypesProvider = FirstPartyHosts(
            ["http://first-party.com/": .init()]
        )
        XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: URL(string: "http://first-party.com/")), .init())
    }

    func testGivenValidDictionary_itReturnsTracingHeaderTypes_forSubdomainURL() {
        let firstPartyHosts = FirstPartyHosts([
            "first-party.com": .init([.b3m]),
            "example.com": [.dd, .b3m],
            "subdomain.example.com": [.w3c],
            "otherdomain.com": [.b3s]
        ])

        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://example.com/path1")), [.dd, .b3m])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://subdomain.example.com/path2")), [.w3c, .dd, .b3m])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://otherdomain.com/path3")), [.b3s])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://somedomain.com/path4")), [])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "api.first-party.com")), [.b3m])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "apifirst-party.com")), [])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://api.first-party.com/v1/endpoint")), [.b3m])
    }

    func testGivenValidDictionary_itReturnsCorrectTracingHeaderTypes() {
        let headerTypesProvider = FirstPartyHosts(hostsDictionary)
        hostsDictionary.keys.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init(arrayLiteral: .w3c, .b3s))
        }
        otherHosts.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init())
        }
    }

    func testGivenFilterIsInitializedWithEmptySet_itNeverReturnsFirstParty() {
        let filter = FirstPartyHosts([:])
        (hostsDictionary.keys + otherHosts).forEach { fixture in
            let url = URL(string: fixture)!
            XCTAssertFalse(
                filter.isFirstParty(url: url),
                "The url: `\(url)` should NOT be matched as first party."
            )
        }
    }

    func testGivenURLHostIsSubdomain_itIsConsideredFirstParty() {
        let filter = FirstPartyHosts([
            "first-party.com": .init([.dd])
        ])
        let url = URL(string: "https://api.first-party.com")!
        XCTAssertTrue(
            filter.isFirstParty(url: url),
            "The url: `\(url)` should NOT be matched as first party."
        )
    }

    func testGivenURLHostIsNotSubdomain_itIsNotConsideredFirstParty() {
        let filter = FirstPartyHosts([
            "first-party.com": .init([.dd])
        ])
        let urlString = "https://apifirst-party.com"
        let url = URL(string: urlString)!
        XCTAssertFalse(
            filter.isFirstParty(url: url),
            "The url: `\(url)` should NOT be matched as first party."
        )
        XCTAssertFalse(
            filter.isFirstParty(string: urlString),
            "The url: `\(urlString)` should NOT be matched as first party."
        )
    }

    func testGivenWRongURL_itIsNotConsideredFirstParty() {
        let filter = FirstPartyHosts([
            "first-party.com": .init([.dd])
        ])
        let badUrlString = ""
        let badUrl = URL(string: badUrlString)
        XCTAssertFalse(
            filter.isFirstParty(url: badUrl),
            "The url: `\(String(describing: badUrl))` should NOT be matched as first party."
        )
        XCTAssertFalse(
            filter.isFirstParty(string: badUrlString),
            "The url: `\(badUrlString)` should NOT be matched as first party."
        )
    }
}
