/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if canImport(CoreTelephony)
import CoreTelephony
#endif

import DatadogInternal
import TestUtilities

@testable import DatadogLogs
@testable import DatadogRUM
@testable import DatadogCrashReporting
@testable import DatadogCore

/// This suite tests if `CrashContextProvider` gets updated by different SDK components, each updating
/// separate part of the `CrashContext` information.
class CrashContextProviderTests: XCTestCase {
    private let provider = CrashContextCoreProvider()

    // MARK: - Receiving SDK Context

    func testWhenInitialSDKContextIsReceived_itNotifiesCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
    }

    func testWhenNextSDKContextIsReceived_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore())) // receive next

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
    }

    // MARK: - Receiving RUM View

    func testWhenRUMViewIsReceivedAfterSDKContext_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()
        let rumView: RUMViewEvent = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .payload(rumView), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
        DDAssertJSONEqual(crashContext.lastRUMViewEvent, rumView, "Last RUM view must be available")
    }

    func testWhenSDKContextIsReceivedAfterRUMView_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let rumView: RUMViewEvent = .mockRandom()
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumView), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
        DDAssertJSONEqual(crashContext.lastRUMViewEvent, rumView, "Last RUM view must be available even after next SDK context update")
    }

    // MARK: - Receiving RUM View Reset

    func testWhenRUMViewResetIsReceivedAfterRUMView_thenItNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()
        let rumView: RUMViewEvent = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumView), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .payload(RUMPayloadMessages.viewReset), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
        XCTAssertNil(crashContext.lastRUMViewEvent, "Last RUM view must reset")
    }

    func testWhenSDKContextIsReceivedAfterRUMViewReset_thenItNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let rumView: RUMViewEvent = .mockRandom()
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumView), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .payload(RUMPayloadMessages.viewReset), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
        XCTAssertNil(crashContext.lastRUMViewEvent, "Last RUM view must reset even after next SDK context update")
    }

    // MARK: - Receiving RUM Session State

    func testWhenRUMSessionStateIsReceivedAfterSDKContext_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()
        let rumSessionState: RUMSessionState = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumSessionState), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
        XCTAssertEqual(crashContext.lastRUMSessionState, rumSessionState, "Last RUM session state must be available")
    }

    func testWhenSDKContextIsReceivedAfterRUMSessionState_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let rumSessionState: RUMSessionState = .mockRandom()
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumSessionState), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
        XCTAssertEqual(crashContext.lastRUMSessionState, rumSessionState, "Last RUM session state must be available even after next SDK context update")
    }

    // MARK: - Receiving Global RUM Attributes

    func testWhenRUMAttributesAreReceivedAfterSDKContext_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()
        let rumAttributes: RUMEventAttributes = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumAttributes), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
        DDAssertJSONEqual(crashContext.lastRUMAttributes, rumAttributes, "Last RUM attributes must be available")
    }

    func testWhenSDKContextIsReceivedAfterRUMAttributes_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let rumAttributes: RUMEventAttributes = .mockRandom()
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(rumAttributes), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
        DDAssertJSONEqual(crashContext.lastRUMAttributes, rumAttributes, "Last RUM attributes must be available even after next SDK context update")
    }

    // MARK: - Receiving Global Log Attributes

    func testWhenLogAttributesAreReceivedAfterSDKContext_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let sdkContext: DatadogContext = .mockRandom()
        let logAttributes: LogEventAttributes = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(sdkContext), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(logAttributes), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: sdkContext)
        DDAssertJSONEqual(crashContext.lastLogAttributes, logAttributes, "Last Log attributes must be available")
    }

    func testWhenSDKContextIsReceivedAfterLogAttributes_itNotifiesNewCrashContext() throws {
        var latestCrashContext: CrashContext? = nil
        provider.onCrashContextChange = { latestCrashContext = $0 }

        // Given
        let logAttributes: LogEventAttributes = .mockRandom()
        let nextSDKContext: DatadogContext = .mockRandom()

        // When
        XCTAssertTrue(provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore())) // receive initial SDK context
        XCTAssertTrue(provider.receive(message: .payload(logAttributes), from: NOPDatadogCore()))
        XCTAssertTrue(provider.receive(message: .context(nextSDKContext), from: NOPDatadogCore()))

        // Then
        provider.flush()
        let crashContext = try XCTUnwrap(latestCrashContext)
        XCTAssertEqual(crashContext, provider.currentCrashContext)
        DDAssert(crashContext: crashContext, includes: nextSDKContext)
        DDAssertJSONEqual(crashContext.lastLogAttributes, logAttributes, "Last Log attributes must be available even after next SDK context update")
    }

    // MARK: - Thread safety

    func testWhenContextIsWrittenAndReadFromDifferentThreads_itRunsAllOperationsSafely() {
        let provider = CrashContextCoreProvider()
        let viewEvent: RUMViewEvent = .mockRandom()
        let sessionState: RUMSessionState = .mockRandom()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = provider.currentCrashContext },
                { _ = provider.receive(message: .context(.mockRandom()), from: NOPDatadogCore()) },
                { _ = provider.receive(message: .payload(viewEvent), from: NOPDatadogCore()) },
                { _ = provider.receive(message: .payload(RUMPayloadMessages.viewReset), from: NOPDatadogCore()) },
                { _ = provider.receive(message: .payload(sessionState), from: NOPDatadogCore()) },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace

        provider.flush()
    }

    // MARK: - Helpers

    private func DDAssert(crashContext: CrashContext, includes sdkContext: DatadogContext, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(crashContext.appLaunchDate, sdkContext.launchInfo.processLaunchDate, file: file, line: line)
        XCTAssertEqual(crashContext.serverTimeOffset, sdkContext.serverTimeOffset, file: file, line: line)
        XCTAssertEqual(crashContext.service, sdkContext.service, file: file, line: line)
        XCTAssertEqual(crashContext.env, sdkContext.env, file: file, line: line)
        XCTAssertEqual(crashContext.version, sdkContext.version, file: file, line: line)
        XCTAssertEqual(crashContext.buildNumber, sdkContext.buildNumber, file: file, line: line)
        DDAssertReflectionEqual(crashContext.device, sdkContext.normalizedDevice(), file: file, line: line)
        DDAssertReflectionEqual(crashContext.os, sdkContext.os, file: file, line: line)
        XCTAssertEqual(crashContext.sdkVersion, sdkContext.sdkVersion, file: file, line: line)
        XCTAssertEqual(crashContext.source, sdkContext.source, file: file, line: line)
        XCTAssertEqual(crashContext.trackingConsent, sdkContext.trackingConsent, file: file, line: line)
        DDAssertReflectionEqual(crashContext.userInfo, sdkContext.userInfo, file: file, line: line)
        DDAssertReflectionEqual(crashContext.accountInfo, sdkContext.accountInfo, file: file, line: line)
        XCTAssertEqual(crashContext.networkConnectionInfo, sdkContext.networkConnectionInfo, file: file, line: line)
        XCTAssertEqual(crashContext.carrierInfo, sdkContext.carrierInfo, file: file, line: line)
        XCTAssertEqual(crashContext.lastIsAppInForeground, sdkContext.applicationStateHistory.currentState.isRunningInForeground, file: file, line: line)
    }
}
