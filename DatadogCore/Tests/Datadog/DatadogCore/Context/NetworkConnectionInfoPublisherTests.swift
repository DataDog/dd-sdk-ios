/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Network
import SystemConfiguration
import DatadogInternal
@testable import DatadogCore

class NWPathMonitorSourceTests: XCTestCase {
    func testNWPathMonitorSourcePublishesValue() async {
        let source = NWPathMonitorSource()

        var iterator = source.values.makeAsyncIterator()
        let value = await iterator.next()
        XCTAssertNotNil(value, "NWPathMonitorSource should yield a value")
    }

    func testNWPathMonitorHandling() {
        let monitor = NWPathMonitor()
        let source = NWPathMonitorSource(monitor: monitor)
        XCTAssertNotNil(source.initialValue)
        XCTAssertNotNil(monitor.pathUpdateHandler, "`NWPathMonitor` has a handler")
        XCTAssertNotNil(monitor.queue, "`NWPathMonitor` is started with synchronization queue")
    }
}

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface

    func testNWPathStatus() {
        XCTAssertEqual(Reachability(.satisfied), .yes)
        XCTAssertEqual(Reachability(.unsatisfied), .no)
        XCTAssertEqual(Reachability(.requiresConnection), .maybe)
    }

    func testNWInterface() {
        XCTAssertEqual(Interface(.wifi), .wifi)
        XCTAssertEqual(Interface(.wiredEthernet), .wiredEthernet)
        XCTAssertEqual(Interface(.loopback), .loopback)
        XCTAssertEqual(Interface(.cellular), .cellular)
        XCTAssertEqual(Interface(.other), .other)
    }
}
