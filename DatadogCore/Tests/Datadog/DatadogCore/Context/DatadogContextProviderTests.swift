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

    func testPublisherPropagation() throws {
        // Given
        let serverOffsetPublisher = ContextValuePublisherMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoPublisher = ContextValuePublisherMock<NetworkConnectionInfo?>()
        let carrierInfoPublisher = ContextValuePublisherMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)
        provider.subscribe(\.serverTimeOffset, to: serverOffsetPublisher)
        provider.subscribe(\.networkConnectionInfo, to: networkConnectionInfoPublisher)
        provider.subscribe(\.carrierInfo, to: carrierInfoPublisher)

        // When
        let serverTimeOffset: TimeInterval = .mockRandomInThePast()
        serverOffsetPublisher.value = serverTimeOffset

        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        networkConnectionInfoPublisher.value = networkConnectionInfo

        let carrierInfo: CarrierInfo = .mockRandom()
        carrierInfoPublisher.value = carrierInfo

        // Then
        let context = provider.read()
        XCTAssertEqual(context.serverTimeOffset, serverTimeOffset)
        XCTAssertEqual(context.networkConnectionInfo, networkConnectionInfo)
        XCTAssertEqual(context.carrierInfo, carrierInfo)
    }

    func testPublishNewContextOnValueChange() throws {
        let expectation = self.expectation(description: "publish new context")
        expectation.expectedFulfillmentCount = 3

        // Given
        let serverOffsetPublisher = ContextValuePublisherMock<TimeInterval>(initialValue: 0)

        let provider = DatadogContextProvider(context: context)
        provider.subscribe(\.serverTimeOffset, to: serverOffsetPublisher)

        provider.publish { _ in
            expectation.fulfill()
        }

        // When
        (0..<expectation.expectedFulfillmentCount).forEach { _ in
            serverOffsetPublisher.value = .mockRandomInThePast()
        }

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Thread Safety

    func testThreadSafety() {
        let serverOffsetPublisher = ContextValuePublisherMock<TimeInterval>(initialValue: 0)
        let networkConnectionInfoPublisher = ContextValuePublisherMock<NetworkConnectionInfo?>()
        let carrierInfoPublisher = ContextValuePublisherMock<CarrierInfo?>()

        let provider = DatadogContextProvider(context: context)

        provider.subscribe(\.serverTimeOffset, to: serverOffsetPublisher)
        provider.subscribe(\.networkConnectionInfo, to: networkConnectionInfoPublisher)
        provider.subscribe(\.carrierInfo, to: carrierInfoPublisher)

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { serverOffsetPublisher.value = .mockRandom() },
                { networkConnectionInfoPublisher.value = .mockRandom() },
                { carrierInfoPublisher.value = .mockRandom() },
                { provider.read { _ in } },
                { provider.write { $0 = .mockAny() } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }

    func testConditionalWrite_whenRefused_itDoesNotMutateOrNotify() {
        let provider = DatadogContextProvider(context: context)
        var writes = 0
        var notifications = 0
        provider.publish { _ in notifications += 1 }

        provider.write(if: { false }) {
            writes += 1
            $0.serverTimeOffset = 42
        }

        let current = provider.read()
        XCTAssertEqual(current.serverTimeOffset, context.serverTimeOffset)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(notifications, 0)
    }

    func testConditionalWrite_whenAdmitted_itMutatesAndNotifiesOnce() {
        let provider = DatadogContextProvider(context: context)
        var writes = 0
        var notifications = 0
        provider.publish { _ in notifications += 1 }

        provider.write(if: { true }) {
            writes += 1
            $0.serverTimeOffset = 42
        }

        XCTAssertEqual(provider.read().serverTimeOffset, 42)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(notifications, 1)
    }

    func testConditionalWrite_preservesExistingReadWriteOrdering() {
        let provider = DatadogContextProvider(context: context)
        var order: [String] = []
        provider.publish { _ in order.append("notification") }

        provider.write {
            order.append("legacy write")
            $0.serverTimeOffset = 1
        }
        provider.read {
            order.append("read")
            XCTAssertEqual($0.serverTimeOffset, 1)
        }
        provider.write(if: {
            order.append("admission")
            return true
        }) {
            order.append("conditional write")
            $0.serverTimeOffset = 2
        }

        XCTAssertEqual(provider.read().serverTimeOffset, 2)
        XCTAssertEqual(order, ["legacy write", "notification", "read", "admission", "conditional write", "notification"])
    }
}
