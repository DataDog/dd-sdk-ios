/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogContextProviderTests: XCTestCase {
    let context: DatadogContext = .mockAny()

    // MARK: - Thread Safety

    func testConcurrentReadWrite() {
        let provider: DatadogContextProvider = .mockWith(context: context)

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            provider.read { _ in }
            provider.write { $0 = .mockAny() }
        }
    }

    // MARK: - Test Propagation

    func testServerOffsetPropagation() throws {
        // Given
        let kronos = KronosClockMock()

        let provider: DatadogContextProvider = .mockWith(
            context: context,
            serverOffsetPublisher: .init(kronos: kronos)
        )

        // When
        let offset: TimeInterval = .mockRandomInThePast()
        kronos.update(offset: offset)

        // Then
        let context = try provider.read()
        XCTAssertEqual(context.serverTimeOffset, offset)
    }

    func testNetworkInfoPropagation() throws {
        // Given
        let publisher = NetworkConnectionInfoPublisherMock()

        let provider: DatadogContextProvider = .mockWith(
            context: context,
            networkConnectionInfoPublisher: publisher.eraseToAnyPublisher()
        )

        // When
        let networkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        publisher.networkConnectionInfo = networkConnectionInfo

        // Then
        let context = try provider.read()
        XCTAssertEqual(context.networkConnectionInfo, networkConnectionInfo)
    }

    func testCarrierInfoPropagation() throws {
        // Given
        let publisher = CarrierInfoPublisherMock()

        let provider: DatadogContextProvider = .mockWith(
            context: context,
            carrierInfoPublisher: .init(publisher)
        )

        // When
        let carrierInfo: CarrierInfo = .mockRandom()
        publisher.carrierInfo = carrierInfo

        // Then
        let context = try provider.read()
        XCTAssertEqual(context.carrierInfo, carrierInfo)
    }
}
