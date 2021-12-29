/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import XCTest
@testable import Datadog

final class KronosDNSResolverTests: XCTestCase {
    func testResolveOneIP() {
        let expectation = self.expectation(description: "Query host's DNS for a single IP")
        KronosDNSResolver.resolve(host: "test.com") { addresses in
            XCTAssertEqual(addresses.count, 1)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 5)
    }

    func testResolveMultipleIP() {
        let expectation = self.expectation(description: "Query host's DNS for multiple IPs")
        KronosDNSResolver.resolve(host: "pool.ntp.org") { addresses in
            XCTAssertGreaterThan(addresses.count, 1)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 5)
    }

    func testResolveIPv6() {
        let expectation = self.expectation(description: "Query host's DNS that supports IPv6")
        KronosDNSResolver.resolve(host: "ipv6friday.org") { addresses in
            XCTAssertGreaterThan(addresses.count, 0)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 5)
    }

    func testInvalidIP() {
        let expectation = self.expectation(description: "Query invalid host's DNS")
        KronosDNSResolver.resolve(host: "l33t.h4x") { addresses in
            XCTAssertEqual(addresses.count, 0)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 5)
    }

    func testTimeout() {
        let expectation = self.expectation(description: "DNS times out")
        KronosDNSResolver.resolve(host: "ip6.nl", timeout: 0) { addresses in
            XCTAssertEqual(addresses.count, 0)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 1.0)
    }

    func testTemporaryRunloopHandling() {
        let expectation = self.expectation(description: "Query works from async GCD queues")
        DispatchQueue(label: "Ephemeral DNS test queue").async {
            KronosDNSResolver.resolve(host: "lyft.com") { _ in
                expectation.fulfill()
            }
        }

        self.waitForExpectations(timeout: 5)
    }
}
