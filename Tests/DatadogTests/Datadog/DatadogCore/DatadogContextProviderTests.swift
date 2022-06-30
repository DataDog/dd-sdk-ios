/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

final class ServerDateProviderMock: ServerDateProvider {
    private var update: (TimeInterval) -> Void = { _ in }

    var offset: TimeInterval = .zero {
        didSet { update(offset) }
    }

    func synchronize(update: @escaping (TimeInterval) -> Void) {
        self.update = update
    }
}

class DatadogContextProviderTests: XCTestCase {
    let context: DatadogContext = .mockAny()

    // MARK: - Thread Safety

    func testConcurrentReadWrite() {
        let provider = DatadogContextProvider(
            context: context,
            serverDateProvider: ServerDateProviderMock()
        )

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            provider.read { _ in }
            provider.write { $0 = .mockAny() }
        }
    }

    func testServerDateProvider() {
        // Given
        let serverDateProvider = ServerDateProviderMock()

        let provider = DatadogContextProvider(
            context: context,
            serverDateProvider: serverDateProvider
        )

        // When
        serverDateProvider.offset = -1

        // Then
        var context = provider.read()
        XCTAssertEqual(context.serverTimeOffset, -1)

        // When
        serverDateProvider.offset = 1

        // Then
        context = provider.read()
        XCTAssertEqual(context.serverTimeOffset, 1)
    }
}
