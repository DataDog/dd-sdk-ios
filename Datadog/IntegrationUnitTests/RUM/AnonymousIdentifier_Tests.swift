/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

/// Mirrors `AnonymousIdentifierTests` with `featureFlags[.viewUpdates] = true`.
/// Verifies that anonymous identifiers are correctly propagated on the first (full) view event
/// when the delta-projection pipeline is active.
class AnonymousIdentifier_Tests: XCTestCase {
    var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
    }

    func test_itGeneratesAnonymousIdentifier() throws {
        enableRUM(trackAnonymousUser: true)

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: true, in: session)
    }

    func test_itDoesNotGenerateAnonymousIdentifierWhenDisabled() throws {
        enableRUM(trackAnonymousUser: false)

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: false, in: session)
    }

    func test_itReusesAnonymousIdentifierOnSubsequentSessions() throws {
        enableRUM(trackAnonymousUser: true)

        let session1 = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: true, in: session1)
        let anonymousId1 = session1.views.last?.viewEvents.first?.usr?.anonymousId

        simulateNewSession()

        enableRUM(trackAnonymousUser: true)

        let session2 = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: true, in: session2)
        let anonymousId2 = session2.views.last?.viewEvents.first?.usr?.anonymousId
        XCTAssertEqual(anonymousId1, anonymousId2)
    }

    func test_itClearsAnonymousIdentifierWhenDisabled() throws {
        enableRUM(trackAnonymousUser: true)

        let session1 = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: true, in: session1)

        simulateNewSession()

        enableRUM(trackAnonymousUser: false)

        let session2 = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: false, in: session2)
    }

    private func simulateNewSession() {
        core = DatadogCoreProxy()
    }

    private func enableRUM(trackAnonymousUser: Bool) {
        var rumConfig = RUM.Configuration(applicationID: .mockAny(), trackAnonymousUser: trackAnonymousUser)
        rumConfig.featureFlags = [.viewUpdates: true]
        RUM.enable(with: rumConfig, in: core)
        // Needs to flush datastore on the caller thread to ensure anonymousId was read from the file.
        core.scope(for: RUMFeature.self).dataStore.flush()
        // Create new view that should consist of anonymousId is present.
        RUMMonitor.shared(in: core).startView(key: .mockRandom(), name: .mockRandom())
    }

    private func assertAnonymousIdentifier(isSet: Bool, in session: RUMSessionMatcher) {
        // The anonymous ID is set on the first (full) RUMViewEvent, unchanged in subsequent deltas.
        if isSet {
            XCTAssertNotNil(session.views.last?.viewEvents.first?.usr?.anonymousId)
        } else {
            XCTAssertNil(session.views.last?.viewEvents.first?.usr?.anonymousId)
        }
    }
}
