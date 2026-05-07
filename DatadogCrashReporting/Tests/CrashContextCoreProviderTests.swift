/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCrashReporting

class CrashContextCoreProviderTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: PassthroughCoreMock!
    private var provider: CrashContextCoreProvider!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
        provider = CrashContextCoreProvider()
        provider.subscribe(to: core.messageBus)
    }

    override func tearDown() {
        core = nil
        provider = nil
        super.tearDown()
    }

    // MARK: - Context Update Tests

    func testItUpdatesContextFromDatadogContext() {
        // When
        XCTAssertTrue(provider.receive(message: .context(.mockWith(
            service: "test-service",
            env: "test-env",
            version: "1.0.0"
        )), from: core))
        provider.flush()

        // Then
        XCTAssertEqual(provider.currentCrashContext?.service, "test-service")
        XCTAssertEqual(provider.currentCrashContext?.env, "test-env")
        XCTAssertEqual(provider.currentCrashContext?.version, "1.0.0")
    }

    func testItDoesNotUpdateContextWhenContextIsUnchanged() {
        // Given
        let context: DatadogContext = .mockWith(service: "test-service")
        var callbackCount = 0
        provider.onCrashContextChange = { _ in callbackCount += 1 }

        // When
        XCTAssertTrue(provider.receive(message: .context(context), from: core))
        XCTAssertTrue(provider.receive(message: .context(context), from: core))
        provider.flush()

        // Then — callback fires once per distinct value
        XCTAssertEqual(callbackCount, 1)
    }

    // MARK: - RUM View Event Tests

    func testItStoresRUMViewEvent() {
        // Given
        let viewEvent: RUMViewEvent = .mockRandom()
        XCTAssertTrue(provider.receive(message: .context(.mockAny()), from: core))

        // When
        core.messageBus.send(message: viewEvent)
        provider.flush()

        // Then
        XCTAssertEqual(provider.currentCrashContext?.lastRUMViewEvent?.view.id, viewEvent.view.id)
    }

    func testItResetsRUMViewEventOnViewReset() {
        // Given
        let viewEvent: RUMViewEvent = .mockRandom()
        XCTAssertTrue(provider.receive(message: .context(.mockAny()), from: core))
        core.messageBus.send(message: viewEvent)
        provider.flush()
        XCTAssertNotNil(provider.currentCrashContext?.lastRUMViewEvent)

        // When
        core.messageBus.send(message: RUMViewReset())
        provider.flush()

        // Then
        XCTAssertNil(provider.currentCrashContext?.lastRUMViewEvent)
    }

    // MARK: - RUM Session State Tests

    func testItStoresRUMSessionState() {
        // Given
        let sessionState: RUMSessionState = .mockRandom()
        XCTAssertTrue(provider.receive(message: .context(.mockAny()), from: core))
        provider.flush()

        // When
        core.messageBus.send(message: sessionState)
        provider.flush()

        // Then
        XCTAssertEqual(provider.currentCrashContext?.lastRUMSessionState?.sessionUUID, sessionState.sessionUUID)
    }

    // MARK: - Callback Tests

    func testItInvokesCallbackOnContextChange() {
        // Given
        var receivedContext: CrashContext?
        provider.onCrashContextChange = { receivedContext = $0 }
        provider.flush()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockWith(service: "test-service")), from: core))
        provider.flush()

        // Then
        XCTAssertEqual(receivedContext?.service, "test-service")
    }

    // MARK: - Message Handling Tests

    func testItReturnsFalseForUnhandledMessages() {
        // When
        let handled = provider.receive(message: .payload("unrelated"), from: core)

        // Then
        XCTAssertFalse(handled)
    }
}
