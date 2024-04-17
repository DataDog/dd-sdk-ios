/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import HTTPServerMock
import XCTest

class WebViewScenarioTest: IntegrationTests, RUMCommonAsserts {
    /// In this test, the app opens a WebView which loads Browser SDK instrumented content.
    /// The iOS SDK should capture all RUM events and Logs produced by Browser SDK.
    func testWebViewEventsScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()
        // Server session recording Logs send to `HTTPServerMock`.
        let loggingServerSession = server.obtainUniqueRecordingSession()
        // Server session recording Replays send to `HTTPServerMock`.
        let srServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "WebViewTrackingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL,
                rumEndpoint: rumServerSession.recordingURL,
                srEndpoint: srServerSession.recordingURL
            )
        )

        // Get single RUM Session with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests, eventsPatch: patchBrowserEvents)?.views.count == 3
        }
        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests, eventsPatch: patchBrowserEvents))
        sendCIAppLog(session)

        XCTAssertEqual(session.views.count, 3, "There should be 3 RUM views - two native and one received from Browser SDK")

        // Check iOS SDK events:
        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        let nativeView = session.views[1]
        XCTAssertEqual(nativeView.name, "Runner.WebViewTrackingFixtureViewController")
        XCTAssertEqual(nativeView.path, "Runner.WebViewTrackingFixtureViewController")

        nativeView.viewEvents.forEach { nativeViewEvent in
            XCTAssertEqual(nativeViewEvent.source, .ios)
        }
        XCTAssertEqual(nativeView.actionEvents.count, 1, "It should track 1 native actions")

        // Check Browser SDK events:
        let expectedBrowserServiceName = "shopist-web-ui"
        let expectedBrowserRUMApplicationID = nativeView.viewEvents[0].application.id
        let expectedBrowserSessionID = nativeView.viewEvents[0].session.id
        let expectedBrowserContainerViewID = nativeView.viewEvents[0].view.id

        let browserView = session.views[2]
        XCTAssertNil(browserView.name, "Browser views should have no `name`")
        XCTAssertEqual(browserView.path, "https://shopist.io/")

        browserView.viewEvents.forEach { browserViewEvent in
            XCTAssertEqual(browserViewEvent.application.id, expectedBrowserRUMApplicationID, "Webview events should use iOS SDK application ID")
            XCTAssertEqual(browserViewEvent.session.id, expectedBrowserSessionID, "Webview events should use iOS SDK session ID")
            XCTAssertEqual(browserViewEvent.service, expectedBrowserServiceName, "Webview events should use Browser SDK `service`")
            XCTAssertEqual(browserViewEvent.source, .browser, "Webview events should use Browser SDK `source`")
            XCTAssertEqual(browserViewEvent.container?.source, .ios, "Webview events should include a container source")
            XCTAssertEqual(browserViewEvent.container?.view.id, expectedBrowserContainerViewID, "Webview events should include a container view.id")
        }
        XCTAssertGreaterThan(browserView.resourceEvents.count, 0, "It should track some Webview resources")
        browserView.resourceEvents.forEach { browserResourceEvent in
            XCTAssertEqual(browserResourceEvent.application.id, expectedBrowserRUMApplicationID, "Webview events should use iOS SDK application ID")
            XCTAssertEqual(browserResourceEvent.session.id, expectedBrowserSessionID, "Webview events should use iOS SDK session ID")
            XCTAssertEqual(browserResourceEvent.service, expectedBrowserServiceName, "Webview events should use Browser SDK `service`")
            XCTAssertEqual(browserResourceEvent.source, .browser, "Webview events should use Browser SDK `source`")
            XCTAssertEqual(browserResourceEvent.container?.source, .ios, "Webview events should use include a container view")
            XCTAssertEqual(browserResourceEvent.container?.view.id, expectedBrowserContainerViewID, "Webview events should include a container view.id")
        }

        // Get `LogMatchers`
        let recordedRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count >= 1 // get at least one log
        }
        let logMatchers = try LogMatcher.from(requests: recordedRequests)

        let browserLog = logMatchers[0]
        browserLog.assertService(equals: expectedBrowserServiceName)
        browserLog.assertAttributes(equal: [
            "application_id": expectedBrowserRUMApplicationID,
            "session_id": expectedBrowserSessionID,
        ])
    }
}

/// Patch applied to RUM resource events received from Browser SDK.
///
/// Browser SDK v4.1.0 uses lowercase string values for `resource.method` field, whereas RUM format schema
/// defines it as uppercase string (e.g. `"get"` instead of `"GET"`). Here we patch `resource.method` to be
/// uppercased, so it can be read and validated in `RUMEventMatcher`.
/// This can be removed once `resource.method` is fixed in future Browser SDK version.
///
/// RUMM-2022: Browser SDK support action id as string or as array of strings as defined in schema:
/// https://github.com/DataDog/rum-events-format/blob/master/schemas/rum/_action-child-schema.json#L15L31
/// This is not yet supported by the Swift schema generator, as a workaround we pick the first id when
/// we encounter an array
private func patchBrowserEvents(_ data: Data) throws -> Data {
    var json = try data.toJSONObject()

    if "resource" == json["type"] as? String,
       var resource = json["resource"] as? [String: Any],
       let method = resource["method"] as? String {
        resource["method"] = method.uppercased()
        json["resource"] = resource
    }

    if var action = json["action"] as? [String: Any],
       let ids = action["id"] as? [String] {
        action["id"] = ids.first ?? "" // when action is present, an valid string is expected
        json["action"] = action
    }

    return try JSONSerialization.data(withJSONObject: json, options: [])
}
