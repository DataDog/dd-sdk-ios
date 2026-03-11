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

    func testSourcePropagation() async throws {
        // Given
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoSource = ContextValueSourceMock<NetworkConnectionInfo?>()
        let carrierInfoSource = ContextValueSourceMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)
        await provider.subscribe(to: serverOffsetSource) { $0.serverTimeOffset = $1 }
        await provider.subscribe(to: networkConnectionInfoSource) { $0.networkConnectionInfo = $1 }
        await provider.subscribe(to: carrierInfoSource) { $0.carrierInfo = $1 }

        // When
        let serverTimeOffset: TimeInterval = .mockRandomInThePast()
        serverOffsetSource.value = serverTimeOffset

        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        networkConnectionInfoSource.value = networkConnectionInfo

        let carrierInfo: CarrierInfo = .mockRandom()
        carrierInfoSource.value = carrierInfo

        // Allow async stream propagation
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        let readContext = await provider.read()
        XCTAssertEqual(readContext.serverTimeOffset, serverTimeOffset)
        XCTAssertEqual(readContext.networkConnectionInfo, networkConnectionInfo)
        XCTAssertEqual(readContext.carrierInfo, carrierInfo)
    }

    func testPublishNewContextOnValueChange() async throws {
        let expectation = self.expectation(description: "publish new context")
        expectation.expectedFulfillmentCount = 3

        // Given
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)

        let provider = DatadogContextProvider(context: context)
        await provider.subscribe(to: serverOffsetSource) { $0.serverTimeOffset = $1 }

        await provider.publish { _ in
            expectation.fulfill()
        }

        // When
        (0..<expectation.expectedFulfillmentCount).forEach { _ in
            serverOffsetSource.value = .mockRandomInThePast()
        }

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    // MARK: - Thread Safety

    func testThreadSafety() async {
        let serverOffsetSource = ContextValueSourceMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoSource = ContextValueSourceMock<NetworkConnectionInfo?>()
        let carrierInfoSource = ContextValueSourceMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)

        await provider.subscribe(to: serverOffsetSource) { $0.serverTimeOffset = $1 }
        await provider.subscribe(to: networkConnectionInfoSource) { $0.networkConnectionInfo = $1 }
        await provider.subscribe(to: carrierInfoSource) { $0.carrierInfo = $1 }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 {
                group.addTask { serverOffsetSource.value = .mockRandom() }
                group.addTask { networkConnectionInfoSource.value = .mockRandom() }
                group.addTask { carrierInfoSource.value = .mockRandom() }
                group.addTask { _ = await provider.read() }
                group.addTask { await provider.write { $0 = .mockAny() } }
            }
        }
    }
}
