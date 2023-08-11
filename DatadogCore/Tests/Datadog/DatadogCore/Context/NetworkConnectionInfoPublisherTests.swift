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

class NetworkConnectionInfoPublisherTests: XCTestCase {
    // MARK: - iOS 12+

    func testNWPathMonitorPublishValue() {
        if #available(iOS 12.0, tvOS 12, *) {
            let expectation = expectation(description: "NWPathMonitorPublisher publish value")
            let publisher = NWPathMonitorPublisher()
            publisher.publish { _ in expectation.fulfill() }
            waitForExpectations(timeout: 1, handler: nil)
        }
    }

    func testNWPathMonitorHandling() {
        if #available(iOS 12.0, tvOS 12, *) {
            let monitor = NWPathMonitor()
            let publisher = NWPathMonitorPublisher(monitor: monitor)
            publisher.publish { _ in }
            XCTAssertNotNil(monitor.pathUpdateHandler, "`NWPathMonitor` has a handler")
            XCTAssertNotNil(monitor.queue, "`NWPathMonitor` is started with synchronization queue")
        }
    }

    // MARK: - iOS 11

    func testSCNetworkReachabilityReadValue() {
        let reader = SCNetworkReachabilityReader()
        var info: NetworkConnectionInfo? = .init(
            reachability: .maybe,
            availableInterfaces: nil,
            supportsIPv4: false,
            supportsIPv6: false,
            isExpensive: false,
            isConstrained: false
        )

        reader.read(to: &info)
        XCTAssertNil(info?.supportsIPv4)
        XCTAssertNil(info?.supportsIPv6)
        XCTAssertNil(info?.isExpensive)
        XCTAssertNil(info?.isConstrained)
    }
}

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface

    func testNWPathStatus() {
        if #available(iOS 12.0, tvOS 12, *) {
            XCTAssertEqual(Reachability(.satisfied), .yes)
            XCTAssertEqual(Reachability(.unsatisfied), .no)
            XCTAssertEqual(Reachability(.requiresConnection), .maybe)
        }
    }

    func testNWInterface() {
        if #available(iOS 12.0, tvOS 12, *) {
            XCTAssertEqual(Interface(.wifi), .wifi)
            XCTAssertEqual(Interface(.wiredEthernet), .wiredEthernet)
            XCTAssertEqual(Interface(.loopback), .loopback)
            XCTAssertEqual(Interface(.cellular), .cellular)
            XCTAssertEqual(Interface(.other), .other)
        }
    }

    func testSCReachability() {
        let reachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertEqual(Reachability(reachable), .yes)

        let unreachable = SCNetworkReachabilityFlags(arrayLiteral: .connectionOnDemand)
        XCTAssertEqual(Reachability(unreachable), .no)

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertEqual(Reachability(null), .maybe)
    }

    func testSCInterface() {
        let cellular = SCNetworkReachabilityFlags(arrayLiteral: .isWWAN)
        XCTAssertEqual(Interface(cellular), .cellular)

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertNil(Interface(null))

        let nonCellularReachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertNil(Interface(nonCellularReachable))
    }
}
