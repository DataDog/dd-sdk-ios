/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class FirstPartyHostsTests: XCTestCase {
    let hostsDictionary: [String: Set<TracingHeaderType>] = [
        "http://first-party.com/": [.tracecontext, .b3],
        "https://first-party.com/": [.tracecontext, .b3],
        "https://api.first-party.com/v2/users": [.tracecontext, .b3],
        "https://www.first-party.com/": [.tracecontext, .b3],
        "https://login:p4ssw0rd@first-party.com:999/": [.tracecontext, .b3],
        "http://any-domain.eu/": [.tracecontext, .b3],
        "https://any-domain.eu/": [.tracecontext, .b3],
        "https://api.any-domain.eu/v2/users": [.tracecontext, .b3],
        "https://www.any-domain.eu/": [.tracecontext, .b3],
        "https://login:p4ssw0rd@www.any-domain.eu:999/": [.tracecontext, .b3],
        "https://api.any-domain.org.eu/": [.tracecontext, .b3],
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
            "first-party.com": .init([.b3multi]),
            "example.com": [.datadog, .b3multi],
            "subdomain.example.com": [.tracecontext],
            "otherdomain.com": [.b3]
        ])

        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://example.com/path1")), [.datadog, .b3multi])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://subdomain.example.com/path2")), [.tracecontext, .datadog, .b3multi])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://otherdomain.com/path3")), [.b3])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://somedomain.com/path4")), [])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://api.first-party.com")), [.b3multi])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "http://apifirst-party.com")), [])
        XCTAssertEqual(firstPartyHosts.tracingHeaderTypes(for: URL(string: "https://api.first-party.com/v1/endpoint")), [.b3multi])
    }

    func testGivenValidDictionary_itReturnsCorrectTracingHeaderTypes() {
        let headerTypesProvider = FirstPartyHosts(hostsDictionary)
        hostsDictionary.keys.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), [.tracecontext, .b3])
        }
        otherHosts.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init())
        }
    }

    func testGivenValidSet_itAssignsDatadogHeaderType() {
        let hosts = FirstPartyHosts(Set(otherHosts))
        otherHosts.forEach {
            let url = URL(string: $0)
            XCTAssertEqual(hosts.tracingHeaderTypes(for: url), [.datadog])
        }
    }

    func testFalsePositiveURL_itReturnsEmptyTracingHeaderTypes() {
        let filter = FirstPartyHosts(
            hostsWithTracingHeaderTypes: ["example.com": [.datadog, .b3multi]]
        )
        let url = URL(string: "http://foo.com/something.example.com")

        XCTAssertEqual(filter.tracingHeaderTypes(for: url), [])
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
            "first-party.com": .init([.datadog])
        ])
        let url = URL(string: "https://api.first-party.com")!
        XCTAssertTrue(
            filter.isFirstParty(url: url),
            "The url: `\(url)` should NOT be matched as first party."
        )
    }

    func testGivenURLHostIsNotSubdomain_itIsNotConsideredFirstParty() {
        let filter = FirstPartyHosts([
            "first-party.com": .init([.datadog])
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
            "first-party.com": .init([.datadog])
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
