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
    /// Constantly pulls the `NetworkConnectionInfo` from given provider and fulfills the expectation if value is received.
    private func pullNetworkConnectionInfo(
        from provider: NetworkConnectionInfoProviderType,
        on queue: DispatchQueue,
        thenFulfill expectation: XCTestExpectation
    ) {
        if provider.current != nil {
            expectation.fulfill()
        } else {
            queue.async { self.pullNetworkConnectionInfo(from: provider, on: queue, thenFulfill: expectation) }
        }
    }

    // MARK: - iOS 12+

    func testNWPathNetworkConnectionInfoProviderGivesValue() {
        if #available(iOS 12.0, *) {
            let provider = NWPathNetworkConnectionInfoProvider()

            pullNetworkConnectionInfo(
                from: provider,
                on: DispatchQueue(label: "com.datadoghq.pulling-NWPathNetworkConnectionInfoProvider", target: .global(qos: .utility)),
                thenFulfill: expectation(description: "Receive `NetworkConnectionInfo` from `NWPathNetworkConnectionInfoProvider`")
            )

            waitForExpectations(timeout: 1, handler: nil)
        }
    }

    func testNWPathNetworkConnectionInfoProviderCanBeSafelyAccessedFromConcurrentThreads() {
        if #available(iOS 12.0, *) {
            let provider = NWPathNetworkConnectionInfoProvider()

            DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
                _ = provider.current
            }
        }
    }

    func testNWPathMonitorHandling() {
        if #available(iOS 12.0, *) {
            weak var nwPathMonitorWeakReference: NWPathMonitor?

            autoreleasepool {
                let nwPathMonitor = NWPathMonitor()
                _ = NWPathNetworkConnectionInfoProvider(monitor: nwPathMonitor)
                nwPathMonitorWeakReference = nwPathMonitor
                XCTAssertNotNil(nwPathMonitor.queue, "`NWPathMonitor` is started with synchronization queue")
            }

            Thread.sleep(forTimeInterval: 0.5)

            XCTAssertNil(nwPathMonitorWeakReference, "`NWPathMonitor` is deallocated with `NWPathNetworkConnectionInfoProvider`")
        }
    }

    // MARK: - iOS 11

    func testiOS11NetworkConnectionInfoProviderGivesValue() {
        let provider = iOS11NetworkConnectionInfoProvider()

        pullNetworkConnectionInfo(
            from: provider,
            on: DispatchQueue(label: "com.datadoghq.pulling-iOS11NetworkConnectionInfoProvider", target: .global(qos: .utility)),
            thenFulfill: expectation(description: "Receive `NetworkConnectionInfo` from `iOS11NetworkConnectionInfoProvider`")
        )

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testiOS11NetworkConnectionInfoProviderCanBeSafelyAccessedFromConcurrentThreads() {
        let provider = iOS11NetworkConnectionInfoProvider()

        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            _ = provider.current
        }
    }
}

class NetworkConnectionInfoConversionTests: XCTestCase {
    typealias Reachability = NetworkConnectionInfo.Reachability
    typealias Interface = NetworkConnectionInfo.Interface

    func testNWPathStatus() {
        if #available(iOS 12.0, *) {
            XCTAssertEqual(Reachability(from: .satisfied), .yes)
            XCTAssertEqual(Reachability(from: .unsatisfied), .no)
            XCTAssertEqual(Reachability(from: .requiresConnection), .maybe)
        }
    }

    func testNWInterface() {
        if #available(iOS 12.0, *) {
            XCTAssertEqual(Array(fromInterfaceTypes: []), [])
            XCTAssertEqual(Array(fromInterfaceTypes: [.wifi]), [.wifi])
            XCTAssertEqual(Array(fromInterfaceTypes: [.wiredEthernet]), [.wiredEthernet])
            XCTAssertEqual(Array(fromInterfaceTypes: [.wifi, .wifi]), [.wifi, .wifi])
            XCTAssertEqual(Array(fromInterfaceTypes: [.wifi, .cellular]), [.wifi, .cellular])
            XCTAssertEqual(Array(fromInterfaceTypes: [.loopback, .other]), [.loopback, .other])
        }
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
        #if !os(OSX)
        let cellular = SCNetworkReachabilityFlags(arrayLiteral: .isWWAN)
        XCTAssertEqual(Array(fromReachabilityFlags: cellular), [.cellular])
        #endif

        let null: SCNetworkReachabilityFlags? = nil
        XCTAssertNil(Array(fromReachabilityFlags: null))

        let nonCellularReachable = SCNetworkReachabilityFlags(arrayLiteral: .reachable)
        XCTAssertNil(Array(fromReachabilityFlags: nonCellularReachable))
    }
}
