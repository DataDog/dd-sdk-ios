/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMConnectivityInfoProviderTests: XCTestCase {
    private let networkInfoProvider = NetworkConnectionInfoProviderMock(networkConnectionInfo: .mockAny())
    private let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: .mockAny())
    private lazy var rumConnectivityInfoProvider = RUMConnectivityInfoProvider(
        networkConnectionInfoProvider: networkInfoProvider,
        carrierInfoProvider: carrierInfoProvider
    )

    func testWhenBothNetworkAndCarrierInfoAreAvailable() throws {
        func verifyConnectivity(
            networkInfo: NetworkConnectionInfo,
            carrierInfo: CarrierInfo,
            verification: (RUMConnectivity) -> Void
        ) throws {
            networkInfoProvider.set(current: networkInfo)
            carrierInfoProvider.set(current: carrierInfo)
            verification(try XCTUnwrap(rumConnectivityInfoProvider.current))
        }

        try verifyConnectivity(
            networkInfo: .mockWith(reachability: .yes, availableInterfaces: [.cellular]),
            carrierInfo: .mockAny()
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.status, .connected)
            XCTAssertEqual(rumConnectivity.interfaces, [.cellular])
        }

        try verifyConnectivity(
            networkInfo: .mockAny(),
            carrierInfo: .mockWith(carrierName: "Carrier Name", radioAccessTechnology: .LTE)
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.cellular?.carrierName, "Carrier Name")
            XCTAssertEqual(rumConnectivity.cellular?.technology, "LTE")
        }

        try verifyConnectivity(
            networkInfo: .mockWith(reachability: .maybe),
            carrierInfo: .mockAny()
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.status, .maybe)
        }

        try verifyConnectivity(
            networkInfo: .mockWith(reachability: .no),
            carrierInfo: .mockAny()
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.status, .notConnected)
        }

        try verifyConnectivity(
            networkInfo: .mockWith(availableInterfaces: [.cellular, .wifi, .wiredEthernet, .loopback, .other]),
            carrierInfo: .mockAny()
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.interfaces, [.cellular, .wifi, .ethernet, .other, .other])
        }

        try verifyConnectivity(
            networkInfo: .mockWith(availableInterfaces: []),
            carrierInfo: .mockAny()
        ) { rumConnectivity in
            XCTAssertEqual(rumConnectivity.interfaces, [.none])
        }
    }

    func testWhenBothNetworkAndCarrierInfoAreNotAvailable() throws {
        networkInfoProvider.set(current: nil)
        carrierInfoProvider.set(current: nil)

        XCTAssertNil(rumConnectivityInfoProvider.current)
    }

    func testWhenNetworkInfoInfoIsNotAvailable() throws {
        networkInfoProvider.set(current: nil)
        carrierInfoProvider.set(current: .mockAny())

        XCTAssertNil(rumConnectivityInfoProvider.current)
    }

    func testWhenCarrierInfoInfoIsNotAvailable() throws {
        networkInfoProvider.set(current: .mockAny())
        carrierInfoProvider.set(current: nil)

        XCTAssertNotNil(rumConnectivityInfoProvider.current)
    }
}
