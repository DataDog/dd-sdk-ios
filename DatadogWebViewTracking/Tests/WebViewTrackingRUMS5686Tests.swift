/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Reproduction tests for RUMS-5686: iOS Web View Tracking Showing Blank Screen In SessionsReplay
///
/// Root cause: When `WebViewTracking.enable()` is called before `SessionReplay.enable()`, the JS bridge
/// capabilities string is baked in as `[]` instead of `["records"]`. The Browser SDK reads capabilities
/// once at page load; if it receives `[]`, it never forwards Session Replay records across the bridge,
/// causing a blank screen in the SR player.
///
/// See: https://datadoghq.atlassian.net/browse/RUMS-5686

#if canImport(WebKit)

import XCTest
import WebKit
import TestUtilities
import DatadogInternal
@testable import DatadogWebViewTracking

// MARK: - Session Replay Feature Fixture

/// A local SessionReplay feature fixture used across RUMS-5686 tests.
private struct MockSessionReplayFeature: DatadogFeature, SessionReplayConfiguration {
    static let name = SessionReplayFeatureName
    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel
    let touchPrivacyLevel: TouchPrivacyLevel

    init(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel = .maskNone,
        touchPrivacyLevel: TouchPrivacyLevel = .show
    ) {
        self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
        self.imagePrivacyLevel = imagePrivacyLevel
        self.touchPrivacyLevel = touchPrivacyLevel
    }
}

// MARK: - Tests

class WebViewTrackingRUMS5686Tests: XCTestCase {
    // MARK: - Test 1: Capabilities baked in as empty when SR not yet initialized

    /// Verifies that when `WebViewTracking.enable()` is called before `SessionReplay` is registered
    /// in the core, `getCapabilities()` returns `'[]'` instead of `'["records"]'`.
    ///
    /// This is the primary reproduction of RUMS-5686: the browser SDK receives empty capabilities at
    /// page load and never enables SR record forwarding, causing a blank screen.
    ///
    /// Expected to FAIL before fix because the correct behavior should be `'["records"]'`
    /// once the SDK detects SR is available — but the current implementation bakes in `[]` statically.
    func testItAddsUserScriptWithEmptyCapabilitiesWhenSessionReplayIsNotYetInitialized() throws {
        // GIVEN: Core with NO Session Replay feature registered (SR will be enabled later)
        let coreWithoutSR = PassthroughCoreMock()

        let controller = DDUserContentController()

        // WHEN: WebViewTracking is enabled before SessionReplay.enable() is called
        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["example.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: coreWithoutSR
        )

        // THEN: The injected script should expose `'["records"]'` so the browser SDK forwards SR records.
        // Currently FAILS because capabilities are baked in as `'[]'` at enable() call time,
        // meaning the browser SDK will never forward Session Replay records → blank screen in SR player.
        let script = try XCTUnwrap(controller.userScripts.last)
        XCTAssertTrue(
            script.source.contains("return '[\"records\"]'"),
            """
            RUMS-5686 reproduction: getCapabilities() returned '[]' instead of '[\"records\"]'.
            WebViewTracking.enable() was called before SessionReplay.enable().
            The JS bridge bakes in capabilities at call time; if SR is not yet registered,
            the browser SDK receives empty capabilities and never enables SR record forwarding,
            causing a blank screen in the Session Replay player.

            Actual script source:
            \(script.source)
            """
        )
    }

    // MARK: - Test 2: Re-enabling WebViewTracking after SR init does not update capabilities

    /// Verifies that once `WebViewTracking.enable()` is called with empty capabilities,
    /// calling `enable()` again after `SessionReplay` is registered does NOT update the injected
    /// script due to the `isTracking` guard — permanently locking the webview in non-SR mode.
    ///
    /// This documents the silent recovery failure that makes RUMS-5686 impossible to work around
    /// at runtime without an explicit `disable()` + `enable()` cycle.
    ///
    /// Expected to FAIL before fix because the test asserts that re-calling enable() after SR
    /// registration SHOULD update the capabilities to `'["records"]'`.
    func testReEnablingWebViewTrackingAfterSRInitDoesNotUpdateCapabilities() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // GIVEN: Core without SR — simulates app calling WebViewTracking.enable() at viewDidLoad()
        // before SessionReplay.enable() has been called.
        let coreWithoutSR = PassthroughCoreMock()
        let controller = DDUserContentController()

        // STEP 1: Enable WebViewTracking without SR → capabilities baked in as '[]'
        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["example.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: coreWithoutSR
        )

        let scriptAfterFirstEnable = try XCTUnwrap(controller.userScripts.last)
        // Confirm initial state: capabilities are empty (current behavior)
        XCTAssertTrue(
            scriptAfterFirstEnable.source.contains("return '[]'"),
            "Precondition: first enable() without SR should inject empty capabilities."
        )

        // STEP 2: SessionReplay is now registered (simulates delayed SR.enable() call)
        let coreWithSR = SingleFeatureCoreMock(feature: MockSessionReplayFeature())

        // STEP 3: Customer tries to recover by calling enable() again on the same webview —
        // this is the natural workaround attempt that silently fails.
        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["example.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: coreWithSR
        )

        // THEN: The script count should remain 1 (second call ignored by isTracking guard)
        XCTAssertEqual(
            controller.userScripts.count,
            1,
            "RUMS-5686: Second enable() call was unexpectedly NOT ignored by isTracking guard."
        )

        // THEN: Capabilities should be updated to '["records"]' after SR is registered.
        // Currently FAILS because the isTracking guard silently drops the second enable() call,
        // leaving getCapabilities() returning '[]' indefinitely.
        let scriptAfterSecondEnable = try XCTUnwrap(controller.userScripts.last)
        XCTAssertTrue(
            scriptAfterSecondEnable.source.contains("return '[\"records\"]'"),
            """
            RUMS-5686 reproduction: After registering SessionReplay, calling WebViewTracking.enable()
            again was silently ignored by the isTracking guard. The injected script still returns '[]'
            for getCapabilities(), permanently preventing SR record forwarding for this webview.
            The only workaround is an explicit WebViewTracking.disable() + enable() cycle, which is
            not documented and not expected by customers.

            Script after second enable():
            \(scriptAfterSecondEnable.source)
            """
        )
    }
}

#endif
