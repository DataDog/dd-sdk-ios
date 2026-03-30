/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

class RUMUserInfoTests: RUMSessionTestsBase {
    // MARK: - User Info on View Events

    func testGivenUserSession_whenUserInfoIsSet_itAppearsOnAllViewEvents() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-123", name: "John", email: "john@example.com"))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.appEntersBackground(after: dt2))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        for viewEvent in manualView.viewEvents {
            XCTAssertEqual(viewEvent.usr?.id, "user-123")
            XCTAssertEqual(viewEvent.usr?.name, "John")
            XCTAssertEqual(viewEvent.usr?.email, "john@example.com")
        }
    }

    func testGivenUserSession_whenUserInfoIsSetWithExtraInfo_itAppearsOnEvents() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-456", extraInfo: ["plan": "premium", "age": 30]))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.appEntersBackground(after: dt2))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        let lastViewEvent = try XCTUnwrap(manualView.viewEvents.last)
        XCTAssertEqual(lastViewEvent.usr?.id, "user-456")
        XCTAssertEqual((lastViewEvent.usr?.usrInfo["plan"] as? AnyCodable)?.value as? String, "premium")
        XCTAssertEqual((lastViewEvent.usr?.usrInfo["age"] as? AnyCodable)?.value as? Int, 30)
    }

    func testGivenUserSession_whenUserInfoChanges_newViewEventsReflectUpdatedInfo() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-A", name: "Alice"))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.setUserInfo(after: dt2, id: "user-B", name: "Bob"))
            .and(.flushDatadogContext())
            .and(.trackTwoActions(after1: dt3, after2: dt4))
            .and(.appEntersBackground(after: dt5))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        // The first view event should have user A
        let firstViewEvent = try XCTUnwrap(manualView.viewEvents.first)
        XCTAssertEqual(firstViewEvent.usr?.id, "user-A")
        XCTAssertEqual(firstViewEvent.usr?.name, "Alice")

        // Later view events (after user change) should have user B
        let lastViewEvent = try XCTUnwrap(manualView.viewEvents.last)
        XCTAssertEqual(lastViewEvent.usr?.id, "user-B")
        XCTAssertEqual(lastViewEvent.usr?.name, "Bob")
    }

    func testGivenUserSession_whenExtraInfoIsAdded_itMergesWithExistingInfo() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-789", extraInfo: ["key1": "value1"]))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.addUserExtraInfo(after: dt2, ["key2": "value2"]))
            .and(.flushDatadogContext())
            .and(.trackTwoActions(after1: dt3, after2: dt4))
            .and(.appEntersBackground(after: dt5))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        let lastViewEvent = try XCTUnwrap(manualView.viewEvents.last)
        XCTAssertEqual(lastViewEvent.usr?.id, "user-789")
        XCTAssertEqual((lastViewEvent.usr?.usrInfo["key1"] as? AnyCodable)?.value as? String, "value1")
        XCTAssertEqual((lastViewEvent.usr?.usrInfo["key2"] as? AnyCodable)?.value as? String, "value2")
    }

    func testGivenUserSession_whenExtraInfoKeyIsRemovedWithNil_itIsRemovedFromEvents() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-nil", extraInfo: ["keep": "yes", "remove": "no"]))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.addUserExtraInfo(after: dt2, ["remove": nil]))
            .and(.flushDatadogContext())
            .and(.trackTwoActions(after1: dt3, after2: dt4))
            .and(.appEntersBackground(after: dt5))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        let lastViewEvent = try XCTUnwrap(manualView.viewEvents.last)
        XCTAssertEqual(lastViewEvent.usr?.id, "user-nil")
        XCTAssertEqual((lastViewEvent.usr?.usrInfo["keep"] as? AnyCodable)?.value as? String, "yes")
        XCTAssertNil(lastViewEvent.usr?.usrInfo["remove"])
    }

    func testGivenUserSession_whenUserInfoIsCleared_newEventsHaveNoUserInfo() throws {
        // Given
        let session = try userSession()
            .when(.setUserInfo(id: "user-clear", name: "ClearMe", email: "clear@example.com"))
            .and(.startManualView(after: dt1, viewName: manualViewName))
            .and(.clearUserInfo(after: dt2))
            .and(.flushDatadogContext())
            .and(.startManualView(after: dt3, viewName: "SecondView", viewKey: "view2"))
            .and(.appEntersBackground(after: dt4))
            .then()
            .takeSingle()

        // Then
        // The first view should have user info
        let firstView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        let firstViewEvent = try XCTUnwrap(firstView.viewEvents.first)
        XCTAssertEqual(firstViewEvent.usr?.id, "user-clear")
        XCTAssertEqual(firstViewEvent.usr?.name, "ClearMe")

        // The second view should have no user info
        let secondView = try XCTUnwrap(session.views.first(where: { $0.name == "SecondView" }))
        let lastViewEvent = try XCTUnwrap(secondView.viewEvents.last)
        XCTAssertNil(lastViewEvent.usr?.id)
        XCTAssertNil(lastViewEvent.usr?.name)
        XCTAssertNil(lastViewEvent.usr?.email)
    }

    func testGivenUserSession_whenUserInfoIsSetAfterViewStart_laterEventUpdatesReflectIt() throws {
        // Given - start view first with no user info, then set user info and trigger events
        let session = try userSession()
            .when(.startManualView(after: dt1, viewName: manualViewName))
            .and(.setUserInfo(after: dt2, id: "late-user", name: "Late", email: "late@example.com"))
            .and(.flushDatadogContext())
            .and(.trackTwoActions(after1: dt3, after2: dt4))
            .and(.appEntersBackground(after: dt5))
            .then()
            .takeSingle()

        // Then
        let manualView = try XCTUnwrap(session.views.first(where: { $0.name == manualViewName }))
        // First view event (before user was set) should have no user info
        let firstViewEvent = try XCTUnwrap(manualView.viewEvents.first)
        XCTAssertNil(firstViewEvent.usr?.id)

        // Later view events (after user was set) should have user info
        let lastViewEvent = try XCTUnwrap(manualView.viewEvents.last)
        XCTAssertEqual(lastViewEvent.usr?.id, "late-user")
        XCTAssertEqual(lastViewEvent.usr?.name, "Late")
        XCTAssertEqual(lastViewEvent.usr?.email, "late@example.com")
    }
}
