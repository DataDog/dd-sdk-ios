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
        core.messageBus.send(message: DatadogContext.mockWith(
            service: "test-service",
            env: "test-env",
            version: "1.0.0"
        ))
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
        core.messageBus.send(message: context)
        core.messageBus.send(message: context)
        provider.flush()

        // Then — callback fires once per distinct value
        XCTAssertEqual(callbackCount, 1)
    }

    // MARK: - RUM View Event Tests

    func testItStoresRUMViewEvent() {
        // Given
        let viewEvent: RUMViewEvent = .mockRandom()
        core.messageBus.send(message: DatadogContext.mockAny())

        // When
        core.messageBus.send(message: viewEvent)
        provider.flush()

        // Then
        XCTAssertEqual(provider.currentCrashContext?.lastRUMViewEvent?.view.id, viewEvent.view.id)
    }

    func testItResetsRUMViewEventOnViewReset() {
        // Given
        let viewEvent: RUMViewEvent = .mockRandom()
        core.messageBus.send(message: DatadogContext.mockAny())
        core.messageBus.send(message: viewEvent)
        provider.flush()
        XCTAssertNotNil(provider.currentCrashContext?.lastRUMViewEvent)

        // When
        core.messageBus.send(message: RUMViewResetMessage())
        provider.flush()

        // Then
        XCTAssertNil(provider.currentCrashContext?.lastRUMViewEvent)
    }

    // MARK: - RUM Session State Tests

    func testItStoresRUMSessionState() {
        // Given
        let sessionState: RUMSessionState = .mockRandom()
        core.messageBus.send(message: DatadogContext.mockAny())
        provider.flush()

        // When
        core.messageBus.send(message: sessionState)
        provider.flush()

        // Then
        XCTAssertEqual(provider.currentCrashContext?.lastRUMSessionState?.sessionUUID, sessionState.sessionUUID)
    }

    // MARK: - Log Attributes Tests

    func testItStoresLogEventAttributesFromLegacyBus() {
        // Given
        let logAttributes: LogEventAttributes = .mockRandom()
        core.messageBus.send(message: DatadogContext.mockAny())
        provider.flush()

        // When — DatadogLogs still publishes log attributes on the legacy bus
        _ = provider.receive(message: .payload(logAttributes), from: core)
        provider.flush()

        // Then
        DDAssertJSONEqual(provider.currentCrashContext?.lastLogAttributes, logAttributes)
    }

    // MARK: - Callback Tests

    func testItInvokesCallbackOnContextChange() {
        // Given
        var receivedContext: CrashContext?
        provider.onCrashContextChange = { receivedContext = $0 }
        provider.flush()

        // When
        core.messageBus.send(message: DatadogContext.mockWith(service: "test-service"))
        provider.flush()

        // Then
        XCTAssertNotNil(receivedContext)
        XCTAssertEqual(receivedContext?.service, "test-service")
    }

    // MARK: - Initial State Tests

    func testCrashContextIsNilUntilFirstContextMessageIsReceived() {
        // Given
        let provider = CrashContextCoreProvider()
        provider.subscribe(to: core.messageBus)

        // Then — no message sent yet
        XCTAssertNil(provider.currentCrashContext)
    }

    func testCrashContextIsSeedWithInitialContextAfterEnabling() {
        // Given
        let expectedContext: DatadogContext = .mockWith(service: "initial-service")
        let core = PassthroughCoreMock(context: expectedContext)
        let provider = CrashContextCoreProvider()

        // When — simulate what enableOrThrow does:
        provider.subscribe(to: core.messageBus)
        core.scope(for: CrashReportingFeature.self).context { context in
            provider.update(context: context)
        }
        provider.flush()

        // Then — context is immediately available without waiting for a bus mutation
        XCTAssertEqual(provider.currentCrashContext?.service, "initial-service")
    }
}
