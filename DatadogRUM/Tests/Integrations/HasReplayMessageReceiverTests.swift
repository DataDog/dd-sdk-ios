/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities
@testable import DatadogRUM

class HasReplayMessageReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var monitor: Monitor! // swiftlint:disable:this implicitly_unwrapped_optional
    private var receiver: HasReplayMessageReceiver! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        receiver = HasReplayMessageReceiver(monitor: monitor)
    }

    override func tearDown() {
        receiver = nil
        monitor = nil
    }

    func testWhenContextMessageCarriesHasReplay_itUpdatesMonitorWithoutAnyRUMCommand() throws {
        // When
        let context: DatadogContext = .mockWith(
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        _ = receiver.receive(message: .context(context), from: NOPDatadogCore())

        // Then
        let activeContextReader: RUMActiveContextReader = monitor
        XCTAssertEqual(activeContextReader.hasReplay, true)
    }

    func testWhenContextMessageHasNoReplayBaggage_itClearsMonitorSnapshot() throws {
        // Given
        _ = receiver.receive(
            message: .context(.mockWith(additionalContext: [SessionReplayCoreContext.HasReplay(value: true)])),
            from: NOPDatadogCore()
        )

        // When
        _ = receiver.receive(message: .context(.mockAny()), from: NOPDatadogCore())

        // Then
        let activeContextReader: RUMActiveContextReader = monitor
        XCTAssertNil(activeContextReader.hasReplay)
    }

    func testItDoesNotConsumeNonContextMessages() {
        let result = receiver.receive(message: .payload("not-a-context-message"), from: NOPDatadogCore())
        XCTAssertFalse(result)
    }
}
