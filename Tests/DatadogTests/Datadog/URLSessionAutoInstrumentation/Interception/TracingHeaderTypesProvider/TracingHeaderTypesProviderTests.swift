/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingHeaderTypesProviderTests: XCTestCase {
    let hostsWithHeaderTypes: Dictionary<String, Set<TracingHeaderType>> = [
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

    func test_TracingHeaderTypesProviderWithEmptyDictionary_itReturnsDefaultTracingHeaderTypes() {
        let headerTypesProvider = TracingHeaderTypesProvider(
            hostsWithHeaderTypes: [:]
        )
        (hostsWithHeaderTypes.keys + otherHosts).forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init(arrayLiteral: .dd))
        }
    }

    func test_TracingHeaderTypesProviderWithEmptyTracingHeaderTypes_itReturnsNoTracingHeaderTypes() {
        let headerTypesProvider = TracingHeaderTypesProvider(
            hostsWithHeaderTypes: ["http://first-party.com/": .init()]
        )
        XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: URL(string: "http://first-party.com/")), .init())
    }

    func test_TracingHeaderTypesProviderWithValidDictionary_itReturnsTracingHeaderTypes_forSubdomainURL() {
        let headerTypesProvider = TracingHeaderTypesProvider(
            hostsWithHeaderTypes: ["first-party.com/": .init(arrayLiteral: .b3m)]
        )
        XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: URL(string: "api.first-party.com/")), .init(arrayLiteral: .b3m))
    }

    func test_TracingHeaderTypesProviderWithValidDictionary_itReturnsCorrectTracingHeaderTypes() {
        let headerTypesProvider = TracingHeaderTypesProvider(
            hostsWithHeaderTypes: hostsWithHeaderTypes
        )
        hostsWithHeaderTypes.keys.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init(arrayLiteral: .w3c, .b3s))
        }
        otherHosts.forEach { fixture in
            let url = URL(string: fixture)
            XCTAssertEqual(headerTypesProvider.tracingHeaderTypes(for: url), .init(arrayLiteral: .dd))
        }
    }
}
