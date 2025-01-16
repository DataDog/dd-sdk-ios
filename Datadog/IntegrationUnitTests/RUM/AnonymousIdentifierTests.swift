/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

/// Test case covering scenarios of anonymous identifier generation.
class AnonymousIdentifierTests: XCTestCase {
    var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
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
        let anonymousIdFromSession1 = session1.views.last?.viewEvents.first?.usr?.anonymousId
        XCTAssertNotNil(anonymousIdFromSession1)

        simulateNewSession()

        enableRUM(trackAnonymousUser: true)

        let session2 = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        assertAnonymousIdentifier(isSet: true, in: session2)
        let anonymousIdFromSession2 = session2.views.last?.viewEvents.first?.usr?.anonymousId
        XCTAssertEqual(anonymousIdFromSession1, anonymousIdFromSession2)
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
        let rumConfig = RUM.Configuration(applicationID: .mockAny(), trackAnonymousUser: trackAnonymousUser)
        RUM.enable(with: rumConfig, in: core)
        // Needs to flush datastore on the caller thread to ensure anonymousId was read from the file.
        core.scope(for: RUMFeature.self).dataStore.flush()
        // Create new view that should consist of anonymousId is present.
        RUMMonitor.shared(in: core).startView(key: .mockRandom(), name: .mockRandom())
    }

    private func assertAnonymousIdentifier(isSet: Bool, in session: RUMSessionMatcher) {
        // Checks if view added after flush contains anonymousId.
        if isSet {
            XCTAssertNotNil(session.views.last?.viewEvents.first?.usr?.anonymousId)
        } else {
            XCTAssertNil(session.views.last?.viewEvents.first?.usr?.anonymousId)
        }
    }
}
