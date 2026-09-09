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
        let activeContextReader: RUMActiveContextReader = monitor

        // When — a context message carries replay baggage
        _ = receiver.receive(
            message: .context(.mockWith(additionalContext: [SessionReplayCoreContext.HasReplay(value: true)])),
            from: NOPDatadogCore()
        )

        // Then
        XCTAssertEqual(activeContextReader.hasReplay, true)

        // When — a later context message carries no replay baggage
        _ = receiver.receive(message: .context(.mockAny()), from: NOPDatadogCore())

        // Then — the snapshot is cleared
        XCTAssertNil(activeContextReader.hasReplay)
    }

    func testItDoesNotConsumeNonContextMessages() {
        let result = receiver.receive(message: .payload("not-a-context-message"), from: NOPDatadogCore())
        XCTAssertFalse(result)
    }
}
