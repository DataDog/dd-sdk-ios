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

final class KronosNTPClientTests: XCTestCase {
    func testQueryIP() {
        let expectation = self.expectation(description: "NTPClient queries single IPs")

        KronosDNSResolver.resolve(host: "time.apple.com") { addresses in
            XCTAssertGreaterThan(addresses.count, 0)

            KronosNTPClient()
                .query(ip: addresses.first!, version: 3, numberOfSamples: 1) { PDU in
                    XCTAssertNotNil(PDU)

                    XCTAssertGreaterThanOrEqual(PDU!.version, 3)
                    XCTAssertTrue(PDU!.isValidResponse())

                    expectation.fulfill()
                }
        }

        self.waitForExpectations(timeout: 10)
    }

    func testQueryPool() {
        let expectation = self.expectation(description: "Offset from ref clock to local clock are accurate")
        KronosNTPClient().query(pool: "0.pool.ntp.org", numberOfSamples: 1, maximumServers: 1) { offset, _, _ in
            XCTAssertNotNil(offset)

            KronosNTPClient()
                .query(pool: "0.pool.ntp.org", numberOfSamples: 1, maximumServers: 1) { offset2, _, _ in
                    XCTAssertNotNil(offset2)
                    XCTAssertLessThan(abs(offset! - offset2!), 0.10)
                    expectation.fulfill()
                }
        }

        self.waitForExpectations(timeout: 10)
    }

    func testQueryPoolWithIPv6() {
        let expectation = self.expectation(description: "NTPClient queries a pool that supports IPv6")
        KronosNTPClient().query(pool: "2.pool.ntp.org", numberOfSamples: 1, maximumServers: 1) { offset, _, _ in
            XCTAssertNotNil(offset)
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 10)
    }
}
