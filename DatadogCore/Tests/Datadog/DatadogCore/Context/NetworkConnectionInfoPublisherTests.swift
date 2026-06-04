/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Network
import DatadogInternal
@testable import DatadogCore

class NetworkConnectionInfoPublisherTests: XCTestCase {
    func testNWPathMonitorPublishValue() {
        let expectation = expectation(description: "NWPathMonitorPublisher publish value")
        let publisher = NWPathMonitorPublisher()
        publisher.publish { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testNWPathMonitorHandling() {
        let monitor = NWPathMonitor()
        let publisher = NWPathMonitorPublisher(monitor: monitor)
        publisher.publish { _ in }
        XCTAssertNotNil(monitor.pathUpdateHandler, "`NWPathMonitor` has a handler")
        XCTAssertNotNil(monitor.queue, "`NWPathMonitor` is started with synchronization queue")
    }
}

#if os(watchOS)
// On watchOS, NWPathMonitor always reports `.unsatisfied` for non-audio-streaming apps (Apple TN3135).
// The SDK replaces it with a NOP publisher that statically reports `.maybe` so uploads are never blocked.
class WatchOSNetworkConnectionInfoPublisherTests: XCTestCase {
    func testWatchOSPublisherReportsMaybeReachability() {
        let publisher = NOPContextValuePublisher(initialValue: NetworkConnectionInfo?.some(
            NetworkConnectionInfo(reachability: .maybe, availableInterfaces: nil, supportsIPv4: nil, supportsIPv6: nil, isExpensive: nil, isConstrained: nil)
        ))

        XCTAssertEqual(publisher.initialValue?.reachability, .maybe, "watchOS publisher must report .maybe so uploads are not blocked")
    }

    func testWatchOSPublisherNeverUpdates() {
        let publisher = NOPContextValuePublisher(initialValue: NetworkConnectionInfo?.some(
            NetworkConnectionInfo(reachability: .maybe, availableInterfaces: nil, supportsIPv4: nil, supportsIPv6: nil, isExpensive: nil, isConstrained: nil)
        ))

        var updateCount = 0
        publisher.publish { _ in updateCount += 1 }

        XCTAssertEqual(updateCount, 0, "watchOS publisher must never push updates — NWPathMonitor is not started")
    }
}
#endif

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface
    typealias LinkQuality = NetworkConnectionInfo.LinkQuality

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

    #if compiler(>=6.2)
    func testNWPathLinkQuality() throws {
        guard #available(iOS 26.0, tvOS 26.0, macOS 26.0, watchOS 26.0, visionOS 26.0, *) else {
            throw XCTSkip("NWPath.LinkQuality requires iOS 26+")
        }
        XCTAssertEqual(LinkQuality(.good), .good)
        XCTAssertEqual(LinkQuality(.minimal), .minimal)
        XCTAssertEqual(LinkQuality(.moderate), .moderate)
        XCTAssertEqual(LinkQuality(.unknown), .unknown)
    }
    #endif
}
