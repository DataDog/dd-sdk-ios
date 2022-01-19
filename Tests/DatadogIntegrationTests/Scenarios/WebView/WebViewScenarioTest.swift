/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "WebViewTrackingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL,
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        // Get single RUM Session with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests, eventsPatch: patchBrowserResourceEvents)?.viewVisits.count == 2
        }
        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests, eventsPatch: patchBrowserResourceEvents))
        XCTAssertEqual(session.viewVisits.count, 2, "There should be 2 RUM views - one native and one received from Browser SDK")

        // Check iOS SDK events:
        let nativeView = session.viewVisits[0]
        XCTAssertEqual(nativeView.name, "Example.WebViewTrackingFixtureViewController")
        XCTAssertEqual(nativeView.path, "Example.WebViewTrackingFixtureViewController")

        nativeView.viewEvents.forEach { nativeViewEvent in
            XCTAssertEqual(nativeViewEvent.source, .ios)
        }
        XCTAssertEqual(nativeView.actionEvents.count, 2, "It should track 2 native actions")

        // Check Browser SDK events:
        let expectedBrowserServiceName = "shopist-web-ui"
        let expectedBrowserRUMApplicationID = nativeView.viewEvents[0].application.id
        let expectedBrowserSessionID = nativeView.viewEvents[0].session.id

        let browserView = session.viewVisits[1]
        XCTAssertNil(browserView.name, "Browser views should have no `name`")
        XCTAssertEqual(browserView.path, "https://shopist.io/")

        browserView.viewEvents.forEach { browserViewEvent in
            XCTAssertEqual(browserViewEvent.application.id, expectedBrowserRUMApplicationID, "Webview events should use iOS SDK application ID")
            XCTAssertEqual(browserViewEvent.session.id, expectedBrowserSessionID, "Webview events should use iOS SDK session ID")
            XCTAssertEqual(browserViewEvent.service, expectedBrowserServiceName, "Webview events should use Browser SDK `service`")
            XCTAssertEqual(browserViewEvent.source, .browser, "Webview events should use Browser SDK `source`")
        }
        XCTAssertGreaterThan(browserView.resourceEvents.count, 0, "It should track some Webview resources")
        browserView.resourceEvents.forEach { browserResourceEvent in
            XCTAssertEqual(browserResourceEvent.application.id, expectedBrowserRUMApplicationID, "Webview events should use iOS SDK application ID")
            XCTAssertEqual(browserResourceEvent.session.id, expectedBrowserSessionID, "Webview events should use iOS SDK session ID")
            XCTAssertEqual(browserResourceEvent.service, expectedBrowserServiceName, "Webview events should use Browser SDK `service`")
            XCTAssertEqual(browserResourceEvent.source, .browser, "Webview events should use Browser SDK `source`")
        }

        // Get `LogMatchers`
        let recordedRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count >= 1 // get at least one log
        }
        let logMatchers = try LogMatcher.from(requests: recordedRequests)

        let browserLog = logMatchers[0]
        browserLog.assertServiceName(equals: expectedBrowserServiceName)
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
///
/// This can be removed once `resource.method` is fixed in future Browser SDK version.
private func patchBrowserResourceEvents(_ data: Data) throws -> Data {
    var json = try data.toJSONObject()

    if let eventType = json["type"] as? String,
       eventType == "resource",
       var resource = json["resource"] as? [String: Any],
       let method = resource["method"] as? String {
        resource["method"] = method.uppercased()
        json["resource"] = resource
    }

    return try JSONSerialization.data(withJSONObject: json, options: [])
}
