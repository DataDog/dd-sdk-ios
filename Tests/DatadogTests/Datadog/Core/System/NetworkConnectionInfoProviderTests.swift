/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import Network
import SystemConfiguration
@testable import Datadog

class NetworkConnectionInfoProviderTests: XCTestCase {
    @available(iOS 12, *)
    func testProviderRetainsNWPathMonitor() {
        let isStarted: (NWPathMonitor) -> Bool = { monitor in
            return monitor.queue != nil
        }

        var provider: NetworkConnectionInfoProvider?
        autoreleasepool {
            let pathMonitor = NWPathMonitor()
            XCTAssertFalse(isStarted(pathMonitor))
            provider = NetworkConnectionInfoProvider(pathMonitor)
            XCTAssertTrue(isStarted(pathMonitor))
        }

        XCTAssertNotNil(provider?.current, "provider should be working")
    }

    @available(iOS 12, *)
    func testProviderReleasesNWPathMonitor() {
        weak var weakRef: NWPathMonitor? = nil
        autoreleasepool {
            let pathMonitor = NWPathMonitor()
            _ = NetworkConnectionInfoProvider(pathMonitor)
            weakRef = pathMonitor
        }
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertNil(weakRef, "path monitor should be deallocated and nil")
    }

    @available(iOS 12, *)
    func testNWPathMonitorUndocumentedBehavior() {
        weak var weakRef: NWPathMonitor? = nil
        autoreleasepool {
            let pathMonitor = NWPathMonitor()
            weakRef = pathMonitor
        }
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertNotNil(weakRef, "iOS 12 did not use to release NWPathMonitor unless cancel is called, now it is fixed 🙌")
    }

    func testItStartsAndCancelsLegacyPathMonitor() {
        var pathMonitor: iOS11PathMonitor? = iOS11PathMonitor()
        weak var weakMonitor: iOS11PathMonitor? = pathMonitor

        var provider: NetworkConnectionInfoProvider? = NetworkConnectionInfoProvider(pathMonitor!)

        pathMonitor = nil

        XCTAssertNotNil(weakMonitor, "provider should retain pathMonitor")
        XCTAssertNotNil(provider!.current, "provider should be working")

        provider = nil // `cancel()` when deinitialized

        XCTAssertNil(provider)
        XCTAssertNil(weakMonitor, "path monitor should be cancelled and released")
    }
}

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface

    @available(iOS 12, *)
    func testNWPathStatus() {
        XCTAssertEqual(Reachability(from: .satisfied), .yes)
        XCTAssertEqual(Reachability(from: .unsatisfied), .no)
        XCTAssertEqual(Reachability(from: .requiresConnection), .maybe)
    }

    @available(iOS 12, *)
    func testNWInterface() {
        XCTAssertEqual(Array(fromInterfaceTypes: []), [])
        XCTAssertEqual(Array(fromInterfaceTypes: [.wifi]), [.wifi])
        XCTAssertEqual(Array(fromInterfaceTypes: [.wifi, .wifi]), [.wifi, .wifi])
        XCTAssertEqual(Array(fromInterfaceTypes: [.wifi, .cellular]), [.wifi, .cellular])
        XCTAssertEqual(Array(fromInterfaceTypes: [.loopback, .other]), [.loopback, .other])
    }

    func testSCReachability() {
        let reachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertEqual(Reachability(from: reachable), .yes)

        let unreachable = SCNetworkReachabilityFlags(arrayLiteral: .connectionOnDemand)
        XCTAssertEqual(Reachability(from: unreachable), .no)

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertEqual(Reachability(from: null), .maybe)
    }

    func testSCInterface() {
        let cellular = SCNetworkReachabilityFlags(arrayLiteral: .isWWAN)
        XCTAssertEqual(Array(fromReachabilityFlags: cellular), [.cellular])

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertNil(Array(fromReachabilityFlags: null))

        let nonCellularReachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertNil(Array(fromReachabilityFlags: nonCellularReachable))
    }
}
