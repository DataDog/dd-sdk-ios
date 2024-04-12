/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest
import DatadogInternal

private class RUMFixture1Screen: XCUIApplication {
    func tapDownloadResourceButton() {
        buttons["Download Resource"].tap()
    }

    func tapPushNextScreen() -> RUMFixture2Screen {
        _ = buttons["Push Next Screen"].waitForExistence(timeout: 2)
        buttons["Push Next Screen"].tap()
        return RUMFixture2Screen()
    }
}

private class RUMFixture2Screen: XCUIApplication {
    func tapPushNextScreen() {
        buttons["Push Next Screen"].tap()
    }
}

class RUMManualInstrumentationScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMManualInstrumentationScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMManualInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen1 = RUMFixture1Screen()
        screen1.tapDownloadResourceButton()
        let screen2 = screen1.tapPushNextScreen()
        screen2.tapPushNextScreen()

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        let view1 = session.views[1]
        XCTAssertEqual(view1.name, "SendRUMFixture1View")
        XCTAssertEqual(view1.path, "Runner.SendRUMFixture1ViewController")
        XCTAssertNotNil(view1.viewEvents.last?.device)
        XCTAssertNotNil(view1.viewEvents.last?.device?.architecture)
        if let architecture = view1.viewEvents.last?.device?.architecture {
            // i486 is the architecture of the VMs on bitrise
            XCTAssertTrue(
                architecture.starts(with: "x86_64") || architecture.starts(with: "arm") || architecture.starts(with: "i486"),
                "Expected architecture to start with 'x86_64', 'i486' or 'arm'. Got \(architecture)"
            )
        }
        XCTAssertEqual(view1.viewEvents.last?.view.action.count, 1)
        XCTAssertEqual(view1.viewEvents.last?.view.resource.count, 1)
        XCTAssertEqual(view1.viewEvents.last?.view.error.count, 1)
        XCTAssertEqual(view1.actionEvents[0].action.type, .tap)
        XCTAssertEqual(view1.actionEvents[0].action.resource?.count, 1, "Action should track one successful Resource")
        XCTAssertEqual(view1.actionEvents[0].action.error?.count, 1, "Action should track second Resource failure as Error")
        XCTAssertEqual(view1.resourceEvents[0].resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(view1.resourceEvents[0].resource.statusCode, 200)
        XCTAssertEqual(view1.resourceEvents[0].resource.type, .image)
        XCTAssertNotNil(view1.resourceEvents[0].resource.duration) // ~0.1s
        XCTAssertGreaterThan(view1.resourceEvents[0].resource.duration!, 100_000_000 - 1) // ~0.1s
        XCTAssertLessThan(view1.resourceEvents[0].resource.duration!, 1_000_000_000 * 30) // less than 30s (big enough to balance NTP sync)
        XCTAssertEqual(view1.errorEvents[0].error.type, "NSURLErrorDomain - -1011")
        XCTAssertEqual(view1.errorEvents[0].error.message, "Bad response.")
        XCTAssertEqual(
            view1.errorEvents[0].error.stack,
            #"Error Domain=NSURLErrorDomain Code=-1011 "Bad response." UserInfo={NSLocalizedDescription=Bad response.}"#
        )
        XCTAssertEqual(view1.errorEvents[0].error.source, .network)
        XCTAssertEqual(view1.errorEvents[0].error.resource?.url, "https://foo.com/resource/2")
        XCTAssertEqual(view1.errorEvents[0].error.resource?.method, .get)
        XCTAssertEqual(view1.errorEvents[0].error.resource?.statusCode, 400)
        XCTAssertEqual(view1.errorEvents[0].error.fingerprint, "custom-fingerprint")
        let featureFlags = try XCTUnwrap(view1.viewEvents.last?.featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 0)
        RUMSessionMatcher.assertViewWasEventuallyInactive(view1)

        let contentReadyTiming = try XCTUnwrap(view1.viewEventMatchers.last?.timing(named: "content-ready"))
        let firstInteractionTiming = try XCTUnwrap(view1.viewEventMatchers.last?.timing(named: "first-interaction"))
        XCTAssertGreaterThanOrEqual(contentReadyTiming, 50_000)
        XCTAssertLessThan(contentReadyTiming, 1_000_000_000)
        XCTAssertGreaterThan(firstInteractionTiming, 0)
        XCTAssertLessThan(firstInteractionTiming, 5_000_000_000)

        let view2 = session.views[2]
        XCTAssertEqual(view2.name, "SendRUMFixture2View")
        XCTAssertEqual(view2.path, "Runner.SendRUMFixture2ViewController")
        XCTAssertNotNil(view2.viewEvents.last?.device)
        XCTAssertEqual(view2.viewEvents.last?.view.action.count, 0)
        XCTAssertEqual(view2.viewEvents.last?.view.resource.count, 0)
        XCTAssertEqual(view2.viewEvents.last?.view.error.count, 1)
        let viewFeatureFlags = try XCTUnwrap(view2.viewEvents.last?.featureFlags)
        XCTAssertEqual((viewFeatureFlags.featureFlagsInfo["mock_flag_a"] as? AnyCodable)?.value as? Bool, false)
        XCTAssertEqual((viewFeatureFlags.featureFlagsInfo["mock_flag_b"] as? AnyCodable)?.value as? String, "mock_value")
        XCTAssertEqual(view2.errorEvents[0].error.message, "Simulated view error")
        XCTAssertEqual(view2.errorEvents[0].error.source, .source)
        let errorFeatureFlags = try XCTUnwrap(view2.errorEvents[0].featureFlags)
        XCTAssertEqual((errorFeatureFlags.featureFlagsInfo["mock_flag_a"] as? AnyCodable)?.value as? Bool, false)
        XCTAssertEqual((errorFeatureFlags.featureFlagsInfo["mock_flag_b"] as? AnyCodable)?.value as? String, "mock_value")
        RUMSessionMatcher.assertViewWasEventuallyInactive(view2)

        let view3 = session.views[3]
        XCTAssertEqual(view3.name, "SendRUMFixture3View")
        XCTAssertEqual(view3.path, "fixture3-vc")
        XCTAssertNotNil(view3.viewEvents.last?.device)
        XCTAssertEqual(view3.viewEvents.last?.view.action.count, 0)
        XCTAssertEqual(view3.viewEvents.last?.view.resource.count, 0)
        XCTAssertEqual(view3.viewEvents.last?.view.error.count, 1)
        let view3Error = try XCTUnwrap(view3.errorEvents[0])
        XCTAssertEqual(view3Error.error.message, "Simulated view error with fingerprint")
        XCTAssertEqual(view3Error.error.fingerprint, "fake-fingerprint")
    }
}
