/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class DatadogContextProviderTests: XCTestCase {
    let context: DatadogContext = .mockAny()

    // MARK: - Test Propagation

    func testSourcePropagation() throws {
        // Given
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoSource = ContextValueSourceMock<NetworkConnectionInfo?>()
        let carrierInfoSource = ContextValueSourceMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)
        provider.observe(serverOffsetSource) { $0.serverTimeOffset = $1 }
        provider.observe(networkConnectionInfoSource) { $0.networkConnectionInfo = $1 }
        provider.observe(carrierInfoSource) { $0.carrierInfo = $1 }

        // When
        let serverTimeOffset: TimeInterval = .mockRandomInThePast()
        serverOffsetSource.value = serverTimeOffset

        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        networkConnectionInfoSource.value = networkConnectionInfo

        let carrierInfo: CarrierInfo = .mockRandom()
        carrierInfoSource.value = carrierInfo

        // Then - flush to ensure async writes complete
        provider.flush()
        let context = provider.read()
        XCTAssertEqual(context.serverTimeOffset, serverTimeOffset)
        XCTAssertEqual(context.networkConnectionInfo, networkConnectionInfo)
        XCTAssertEqual(context.carrierInfo, carrierInfo)
    }

    func testPublishNewContextOnValueChange() throws {
        let expectation = self.expectation(description: "publish new context")
        expectation.expectedFulfillmentCount = 3

        // Given
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)

        let provider = DatadogContextProvider(context: context)
        provider.observe(serverOffsetSource) { $0.serverTimeOffset = $1 }

        provider.publish { _ in
            expectation.fulfill()
        }

        // When
        (0..<expectation.expectedFulfillmentCount).forEach { _ in
            serverOffsetSource.value = .mockRandomInThePast()
        }

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Thread Safety

    func testThreadSafety() {
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoSource = ContextValueSourceMock<NetworkConnectionInfo?>()
        let carrierInfoSource = ContextValueSourceMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)

        provider.observe(serverOffsetSource) { $0.serverTimeOffset = $1 }
        provider.observe(networkConnectionInfoSource) { $0.networkConnectionInfo = $1 }
        provider.observe(carrierInfoSource) { $0.carrierInfo = $1 }

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { serverOffsetSource.value = .mockRandom() },
                { networkConnectionInfoSource.value = .mockRandom() },
                { carrierInfoSource.value = .mockRandom() },
                { provider.read { _ in } },
                { provider.write { $0 = .mockAny() } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }
}
