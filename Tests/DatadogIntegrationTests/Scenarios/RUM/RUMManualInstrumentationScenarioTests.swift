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

        // Return desired count or timeout
        let recordedRUMRequests = try rumServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        // Assert RUM events
        let rumEventsMatchers = try recordedRUMRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        // Assert common things
        assertHTTPHeadersAndPath(in: recordedRUMRequests)

        // Assert Fixture 1 VC ⬇️

        // ----> `application_start` Action due to initial startView()
        let applicationStartAction: RUMAction = try rumEventsMatchers[0].model()
        XCTAssertEqual(applicationStartAction.action.type, .applicationStart)

        // ----> View update on startView()
        let view1UpdateA: RUMView = try rumEventsMatchers[1].model()
        XCTAssertEqual(view1UpdateA.dd.documentVersion, 1)
        XCTAssertEqual(view1UpdateA.view.action.count, 1)
        XCTAssertEqual(view1UpdateA.view.resource.count, 0)

        // --------> Resource event on stopResourceLoading()
        let resourceLoaded: RUMResource = try rumEventsMatchers[2].model()
        XCTAssertEqual(resourceLoaded.view.id, view1UpdateA.view.id)
        XCTAssertEqual(resourceLoaded.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(resourceLoaded.resource.statusCode, 200)
        XCTAssertEqual(resourceLoaded.resource.type, .image)
        XCTAssertGreaterThan(resourceLoaded.resource.duration, 100_000_000 - 1) // ~0.1s
        XCTAssertLessThan(resourceLoaded.resource.duration, 100_000_000 * 3) // less than 0.3s

        // ----> View update after stopResourceLoading()
        let view1UpdateB: RUMView = try rumEventsMatchers[3].model()
        XCTAssertEqual(view1UpdateB.view.id, view1UpdateA.view.id)
        XCTAssertEqual(view1UpdateB.dd.documentVersion, 2)
        XCTAssertEqual(view1UpdateB.view.action.count, 1)
        XCTAssertEqual(view1UpdateB.view.resource.count, 1)
        XCTAssertEqual(view1UpdateB.view.error.count, 0)

        // --------> Error event on stopResourceLoadingWithError()
        let resourceError: RUMError = try rumEventsMatchers[4].model()
        XCTAssertEqual(resourceError.view.id, view1UpdateA.view.id)
        XCTAssertEqual(resourceError.error.message, "NSURLErrorDomain - -1011")
        XCTAssertEqual(
            resourceError.error.stack,
            #"Error Domain=NSURLErrorDomain Code=-1011 "Bad response." UserInfo={NSLocalizedDescription=Bad response.}"#
        )
        XCTAssertEqual(resourceError.error.source, .network)
        XCTAssertEqual(resourceError.error.resource?.url, "https://foo.com/resource/2")
        XCTAssertEqual(resourceError.error.resource?.method, .methodGET)
        XCTAssertEqual(resourceError.error.resource?.statusCode, 400)

        // ----> View update after stopResourceLoadingWithError()
        let view1UpdateC: RUMView = try rumEventsMatchers[5].model()
        XCTAssertEqual(view1UpdateC.view.id, view1UpdateA.view.id)
        XCTAssertEqual(view1UpdateC.dd.documentVersion, 3)
        XCTAssertEqual(view1UpdateC.view.action.count, 1)
        XCTAssertEqual(view1UpdateC.view.resource.count, 1)
        XCTAssertEqual(view1UpdateC.view.error.count, 1)

        // --------> Action event after tapping "Download Resource" (postponed until Resource finished loading)
        let downloadResourceTap: RUMAction = try rumEventsMatchers[6].model()
        XCTAssertEqual(downloadResourceTap.view.id, view1UpdateA.view.id)
        XCTAssertEqual(downloadResourceTap.action.type, .tap)
        XCTAssertEqual(downloadResourceTap.action.resource?.count, 1, "User Action should track first succesfull Resource")
        XCTAssertEqual(downloadResourceTap.action.error?.count, 1, "User Action should track second Resource failure as Error")

        // ----> View update on stopView()
        let view1UpdateD: RUMView = try rumEventsMatchers[7].model()
        XCTAssertEqual(view1UpdateD.view.id, view1UpdateA.view.id)
        XCTAssertEqual(view1UpdateD.dd.documentVersion, 4)
        XCTAssertEqual(view1UpdateD.view.action.count, 2)
        XCTAssertEqual(view1UpdateD.view.resource.count, 1)
        XCTAssertEqual(view1UpdateD.view.error.count, 1)

        // Assert Fixture 2 VC ⬇️

        // ----> View update on startView()
        let view2UpdateA: RUMView = try rumEventsMatchers[8].model()
        XCTAssertEqual(view2UpdateA.dd.documentVersion, 1)
        XCTAssertEqual(view2UpdateA.view.action.count, 0)
        XCTAssertEqual(view2UpdateA.view.error.count, 0)

        // --------> Error event after starting View 2
        let view2Error: RUMError = try rumEventsMatchers[9].model()
        XCTAssertEqual(view2Error.error.message, "Simulated view error")
        XCTAssertEqual(view2Error.error.source, .source)

        // ----> View update after Error
        let view2UpdateB: RUMView = try rumEventsMatchers[10].model()
        XCTAssertEqual(view2UpdateB.dd.documentVersion, 2)
        XCTAssertEqual(view2UpdateB.view.action.count, 0)
        XCTAssertEqual(view2UpdateB.view.error.count, 1)

        // ----> View update on stopView()
        let view2UpdateC: RUMView = try rumEventsMatchers[11].model()
        XCTAssertEqual(view2UpdateC.dd.documentVersion, 3)
        XCTAssertEqual(view2UpdateC.view.action.count, 0)
        XCTAssertEqual(view2UpdateC.view.error.count, 1)

        // Assert Fixture 3 VC ⬇️

        // ----> View update on startView()
        let view3UpdateA: RUMView = try rumEventsMatchers[12].model()
        XCTAssertEqual(view3UpdateA.dd.documentVersion, 1)
        XCTAssertEqual(view3UpdateA.view.action.count, 0)

        XCTAssertEqual(rumEventsMatchers.count, 13)
    }
}
