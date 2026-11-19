/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal

@testable import DatadogLogs

class WebViewLogReceiverTests: XCTestCase {
    func testParsingLogEvent() throws {
        // Given
        let data = """
        {
          "eventType": "log",
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            },
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": {
              "referrer": "",
              "url": "https://datadoghq.dev/browser-sdk-test-playground"
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """.utf8Data

        // When
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebViewMessage.self, from: data)

        guard case let .log(event) = message else {
            return XCTFail("not a log message")
        }

        // Then
        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("date"), 1_635_932_927_012)
        XCTAssertEqual(try json.value("error.origin"), "console")
        XCTAssertEqual(try json.value("message"), "console error: error")
        XCTAssertEqual(try json.value("session_id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual(try json.value("status"), "error")
        XCTAssertEqual(try json.value("view.referrer"), "")
        XCTAssertEqual(try json.value("view.url"), "https://datadoghq.dev/browser-sdk-test-playground")
    }

    func testReceiveEvent() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()

        let expectation = expectation(description: "Send Event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in expectation.fulfill() }

        let value: String = .mockRandom()

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": value])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let received: AnyEncodable = try XCTUnwrap(core.events().last, "It should send event")
        let expected: [String: Any] = [
            "ddtags": "service:abc,version:abc,sdk_version:abc,env:abc",
            "test": value
        ]

        DDAssertJSONEqual(received, AnyEncodable(expected))
    }

    // MARK: - Web-view log

    func testWhenValidWebLogEventPassed_itDecoratesAndPassesToWriter() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let applicationVersion: String = .mockRandom()
        let environment: String = .mockRandom()
        let mockSessionID: UUID = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                env: environment,
                version: applicationVersion,
                serverTimeOffset: 123,
                additionalContext: [
                    RUMCoreContext(
                        applicationID: "123456",
                        sessionID: mockSessionID.uuidString.lowercased(),
                        sessionSampler: .mockKeepAll()
                    )
                ]
            )
        )

        let webLogEvent: [String: Any] = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(webLogEvent)),
                from: core
            )
        )

        // Then
        let expectedWebLogEvent: [String: Any] = [
            "date": 1_635_932_927_012 + 123.dd.toInt64Milliseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "service:abc,version:\(applicationVersion),sdk_version:abc,env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        let received: AnyEncodable = try XCTUnwrap(core.events().first, "It should send event")
        DDAssertJSONEqual(received, AnyEncodable(expectedWebLogEvent))
    }

    // MARK: - RUM Integration

    func testWhenRUMContextIsAvailable_itSendsLogWithRUMContext() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()
        let viewID: String = .mockRandom()
        let actionID: String = .mockRandom()

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                additionalContext: [
                    RUMCoreContext(
                        applicationID: applicationID,
                        sessionID: sessionID,
                        sessionSampler: DeterministicSampler.mockKeepAll(),
                        viewID: viewID,
                        userActionID: actionID
                    )
                ]
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(core.events.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertEqual(log["application_id"] as? String, applicationID)
        XCTAssertEqual(log["session_id"] as? String, sessionID)
        XCTAssertEqual(log["view.id"] as? String, viewID)
        XCTAssertEqual(log["user_action.id"] as? String, actionID)
    }

    func testWhenRUMContextIsAvailable_butSampledOut_itDoesNotSendTelemetryError() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let telemetryReceiver = TelemetryReceiverMock()
        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                additionalContext: [
                    RUMCoreContext(
                        applicationID: applicationID,
                        sessionID: sessionID,
                        sessionSampler: .mockRejectAll()
                    )
                ]
            ),
            messageReceiver: telemetryReceiver
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertNil(log["application_id"])
        XCTAssertNil(log["session_id"])
        XCTAssertNil(log["view.id"])
        XCTAssertNil(log["user_action.id"])
        XCTAssertTrue(telemetryReceiver.messages.isEmpty)
    }

    func testWhenNoRUMContextIsAvailable_itDoesNotSendTelemetryError() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let telemetryReceiver = TelemetryReceiverMock()
        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(messageReceiver: telemetryReceiver)
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertNil(log["application_id"])
        XCTAssertNil(log["session_id"])
        XCTAssertNil(log["view.id"])
        XCTAssertNil(log["user_action.id"])
        XCTAssertTrue(telemetryReceiver.messages.isEmpty)
    }

    // MARK: - Anonymous ID Propagation

    func testWhenAnonymousIdIsAvailable_itAddsAnonymousIdAndPreservesExistingWebUsrFields() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let fakeAnonymousId: String = .mockRandom()
        let webUsrId: String = .mockRandom()
        let webUsrName: String = .mockRandom()

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                userInfo: UserInfo(anonymousId: fakeAnonymousId)
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log([
                    "test": "value",
                    "usr": ["id": webUsrId, "name": webUsrName]
                ])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let log = try XCTUnwrap(core.events(ofType: AnyEncodable.self).first?.value as? [String: Any])
        let usr = try XCTUnwrap(log["usr"] as? [String: Any])
        XCTAssertEqual(usr["id"] as? String, webUsrId)
        XCTAssertEqual(usr["name"] as? String, webUsrName)
        XCTAssertEqual(usr["anonymous_id"] as? String, fakeAnonymousId)
    }

    func testWhenBrowserAlreadySetAnonymousId_itOverwritesWithNativeValue() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let nativeAnonymousId: String = .mockRandom()
        let browserAnonymousId: String = .mockRandom()

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                userInfo: UserInfo(anonymousId: nativeAnonymousId)
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log([
                    "test": "value",
                    "usr": ["anonymous_id": browserAnonymousId]
                ])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let log = try XCTUnwrap(core.events(ofType: AnyEncodable.self).first?.value as? [String: Any])
        let usr = try XCTUnwrap(log["usr"] as? [String: Any])
        XCTAssertEqual(usr["anonymous_id"] as? String, nativeAnonymousId)
    }

    func testWhenAnonymousIdIsAvailable_andNoUsrSet_itAddsAnonymousId() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let fakeAnonymousId: String = .mockRandom()

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                userInfo: UserInfo(anonymousId: fakeAnonymousId)
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let log = try XCTUnwrap(core.events(ofType: AnyEncodable.self).first?.value as? [String: Any])
        let usr = try XCTUnwrap(log["usr"] as? [String: Any])
        XCTAssertEqual(usr["anonymous_id"] as? String, fakeAnonymousId)
        XCTAssertEqual(usr.count, 1, "usr should only contain anonymous_id")
    }
    func testCapturedWebLog_keepsOriginalViewAndAcceptedAction() throws {
        let owner = RUMContextHandoff.Owner()
        let original = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a", userActionID: "previous-action")
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: original)
        let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: original, sceneIdentifier: "scene-a", hasPendingUserAction: true, excludedUserActionID: "previous-action", actionReceipt: receipt))
        let delivery = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-b", userActionID: "peer-action")
        let core = CapturedWebLogCore(context: .mockWith(serverTimeOffset: 0, additionalContext: [delivery]))
        core.owner = owner
        let message = WebViewMessageWithRUMContext(message: .log(["message": "browser-log"]), capture: capture)
        let receiver = WebViewLogReceiver()
        XCTAssertTrue(receiver.receive(message: .payload(message), from: core))
        receipt.accept(sessionID: "native-session", viewID: "native-a", actionID: "accepted-action")
        XCTAssertTrue(receiver.receive(message: .payload(message), from: core))
        let logs: [AnyEncodable] = core.events()
        XCTAssertEqual(logs.count, 2)
        let pending = try JSONObjectMatcher(logs[0])
        XCTAssertEqual(pending.object[LogEvent.Attributes.RUM.viewID] as? String, "native-a")
        XCTAssertNil(pending.object[LogEvent.Attributes.RUM.actionID])
        let accepted = try JSONObjectMatcher(logs[1])
        XCTAssertEqual(accepted.object[LogEvent.Attributes.RUM.viewID] as? String, "native-a")
        XCTAssertEqual(accepted.object[LogEvent.Attributes.RUM.actionID] as? String, "accepted-action")
    }

    func testCapturedWebLog_keepsLogWithoutBorrowingInvalidOwnership() throws {
        for invalid in [true, false] {
            let owner = RUMContextHandoff.Owner()
            let original = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a")
            let core = CapturedWebLogCore(context: .mockWith(serverTimeOffset: 0, additionalContext: [original]))
            core.owner = invalid ? owner : RUMContextHandoff.Owner()
            if invalid { owner.invalidate() }
            let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: original, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil))
            let message = WebViewMessageWithRUMContext(message: .log(["message": "browser-log", LogEvent.Attributes.RUM.viewID: "unproved-view"]), capture: capture)
            XCTAssertTrue(WebViewLogReceiver().receive(message: .payload(message), from: core))
            let log: AnyEncodable = try XCTUnwrap(core.events().first)
            let json = try JSONObjectMatcher(log)
            XCTAssertEqual(try json.value("message"), "browser-log")
            for key in [LogEvent.Attributes.RUM.applicationID, LogEvent.Attributes.RUM.sessionID, LogEvent.Attributes.RUM.viewID, LogEvent.Attributes.RUM.actionID] {
                XCTAssertNil(json.object[key])
            }
        }
    }

    func testCapturedWebLog_checksLiveSessionAtDeferredDelivery() throws {
        let original = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [original]), deferEventWriteContext: true)
        let core = CapturedWebLogCore()
        let owner = RUMContextHandoff.Owner()
        core.owner = owner
        core.scopeOverride = scope
        let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: original, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil))
        let message = WebViewMessageWithRUMContext(message: .log(["message": "browser-log", LogEvent.Attributes.RUM.viewID: "unproved-peer"]), capture: capture)
        XCTAssertTrue(WebViewLogReceiver().receive(message: .payload(message), from: core))
        core.sessionValidator?.isActive = false
        scope.flushDeferredEventWriteContexts()
        let log: AnyEncodable = try XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first)
        let json = try JSONObjectMatcher(log)
        XCTAssertEqual(try json.value("message"), "browser-log")
        for key in [LogEvent.Attributes.RUM.applicationID, LogEvent.Attributes.RUM.sessionID, LogEvent.Attributes.RUM.viewID, LogEvent.Attributes.RUM.actionID] {
            XCTAssertNil(json.object[key])
        }
        XCTAssertEqual(scope.eventsWritten.count, 1)
        XCTAssertEqual(core.sessionValidator?.calls, 1)
    }

    func testCapturedWebLog_requiresLiveSessionCapability() throws {
        let original = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a")
        let core = CapturedWebLogCore(context: .mockWith(additionalContext: [original]))
        let owner = RUMContextHandoff.Owner()
        core.owner = owner
        core.sessionValidator = nil
        let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: original, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil))
        XCTAssertTrue(WebViewLogReceiver().receive(message: .payload(WebViewMessageWithRUMContext(message: .log(["message": "browser-log"]), capture: capture)), from: core))
        let log: AnyEncodable = try XCTUnwrap(core.events().first)
        let json = try JSONObjectMatcher(log)
        XCTAssertEqual(try json.value("message"), "browser-log")
        XCTAssertNil(json.object[LogEvent.Attributes.RUM.sessionID])
    }

    func testSourceLessWebLog_doesNotReadLiveSessionCapability() throws {
        let original = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a")
        let core = CapturedWebLogCore(context: .mockWith(additionalContext: [original]))
        core.sessionValidator?.isActive = false
        XCTAssertTrue(WebViewLogReceiver().receive(message: .webview(.log(["message": "browser-log"])), from: core))
        let log: AnyEncodable = try XCTUnwrap(core.events().first)
        let json = try JSONObjectMatcher(log)
        XCTAssertEqual(json.object[LogEvent.Attributes.RUM.sessionID] as? String, "native-session")
        XCTAssertEqual(core.sessionValidator?.calls, 0)
    }
}

private final class CapturedWebLogCore: DatadogCoreProtocol, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    let base: PassthroughCoreMock
    var owner: RUMContextHandoff.Owner?
    var sessionValidator: CapturedWebLogSession? = CapturedWebLogSession()
    var scopeOverride: FeatureScope?
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
    var remoteConfiguration: RemoteConfiguration? { base.remoteConfiguration }

    init(context: DatadogContext = .mockAny()) { base = PassthroughCoreMock(context: context) }

    func register<T>(feature: T) throws where T: DatadogFeature {}
    func feature<T>(named name: String, type: T.Type) -> T? {
        name == Feature.rum ? sessionValidator as? T : nil
    }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature { scopeOverride ?? base }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
    func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable { base.events(ofType: type) }
}

private final class CapturedWebLogSession: RUMContextHandoffSessionValidating {
    var isActive = true
    var calls = 0
    func isRUMContextHandoffSessionActive(sessionID: String, owner: RUMContextHandoff.Owner) -> Bool {
        calls += 1
        return isActive
    }
}
