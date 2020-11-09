/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

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
            testScenario: RUMManualInstrumentationScenario.self,
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let screen1 = RUMFixture1Screen()
        screen1.tapDownloadResourceButton()
        let screen2 = screen1.tapPushNextScreen()
        screen2.tapPushNextScreen()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.from(requests: requests)?.viewVisits.count == 3
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.from(requests: recordedRUMRequests))

        let view1 = session.viewVisits[0]
        XCTAssertEqual(view1.path, "SendRUMFixture1ViewController")
        XCTAssertEqual(view1.viewEvents.count, 4, "First view should receive 4 updates")
        XCTAssertEqual(view1.viewEvents.last?.view.action.count, 2)
        XCTAssertEqual(view1.viewEvents.last?.view.resource.count, 1)
        XCTAssertEqual(view1.viewEvents.last?.view.error.count, 1)
        XCTAssertEqual(view1.actionEvents[0].action.type, .applicationStart)
        XCTAssertEqual(view1.actionEvents[1].action.type, .tap)
        XCTAssertEqual(view1.actionEvents[1].action.resource?.count, 1, "Action should track one succesfull Resource")
        XCTAssertEqual(view1.actionEvents[1].action.error?.count, 1, "Action should track second Resource failure as Error")
        XCTAssertEqual(view1.resourceEvents[0].resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(view1.resourceEvents[0].resource.statusCode, 200)
        XCTAssertEqual(view1.resourceEvents[0].resource.type, .image)
        XCTAssertGreaterThan(view1.resourceEvents[0].resource.duration, 100_000_000 - 1) // ~0.1s
        XCTAssertLessThan(view1.resourceEvents[0].resource.duration, 100_000_000 * 3) // less than 0.3s
        XCTAssertEqual(view1.errorEvents[0].error.message, "NSURLErrorDomain - -1011 - Bad response.")
        XCTAssertEqual(
            view1.errorEvents[0].error.stack,
            #"Error Domain=NSURLErrorDomain Code=-1011 "Bad response." UserInfo={NSLocalizedDescription=Bad response.}"#
        )
        XCTAssertEqual(view1.errorEvents[0].error.source, .network)
        XCTAssertEqual(view1.errorEvents[0].error.resource?.url, "https://foo.com/resource/2")
        XCTAssertEqual(view1.errorEvents[0].error.resource?.method, .methodGET)
        XCTAssertEqual(view1.errorEvents[0].error.resource?.statusCode, 400)

        let view2 = session.viewVisits[1]
        XCTAssertEqual(view2.path, "SendRUMFixture2ViewController")
        XCTAssertEqual(view2.viewEvents.last?.view.action.count, 0)
        XCTAssertEqual(view2.viewEvents.last?.view.resource.count, 0)
        XCTAssertEqual(view2.viewEvents.last?.view.error.count, 1)
        XCTAssertEqual(view2.errorEvents[0].error.message, "Simulated view error")
        XCTAssertEqual(view2.errorEvents[0].error.source, .source)

        let view3 = session.viewVisits[2]
        XCTAssertEqual(view3.path, "SendRUMFixture3ViewController")
        XCTAssertEqual(view3.viewEvents.last?.view.action.count, 0)
        XCTAssertEqual(view3.viewEvents.last?.view.resource.count, 0)
        XCTAssertEqual(view3.viewEvents.last?.view.error.count, 0)
    }
}
