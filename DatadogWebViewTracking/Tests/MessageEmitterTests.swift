/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal

@testable import DatadogWebViewTracking
@testable import DatadogRUM
@testable import DatadogLogs

class MessageEmitterTests: XCTestCase {
    // MARK: - Routing

    func testGivenSampleRate100_whenReceivingLogEvent_itForwardsToLogs() throws {
        let sampler = Sampler(samplingRate: 100)

        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "log",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let message = try XCTUnwrap(receiverMock.messages.firstWebViewMessage)
        guard case let .log(event) = message else {
            return XCTFail("not a log message")
        }

        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    func testGivenSampleRate0_whenReceivingLogEvent_itIsDropped() throws {
        let sampler = Sampler(samplingRate: 0)
        let eventType = "log"

        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "\(eventType)",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        XCTAssertNil(receiverMock.messages.firstWebViewMessage)
    }

    func testWhenReceivingRUMEvent_itForwardsToRUM() throws {
        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: .mockRandom(), core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "rum",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let message = try XCTUnwrap(receiverMock.messages.firstWebViewMessage)
        guard case let .rum(event) = message else {
            return XCTFail("not a rum message")
        }

        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    func testWhenReceivingTelemetryEvent_itForwardsToTelemetry() throws {
        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: .mockRandom(), core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "internal_telemetry",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let message = try XCTUnwrap(receiverMock.messages.firstWebViewMessage)
        guard case let .telemetry(event) = message else {
            return XCTFail("not a telemetry message")
        }

        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    // MARK: - Parsing

    func testWhenMessageIsInvalid_itReportTheError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let telemetry = TelemetryReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: telemetry)
        let bridge = MessageEmitter(logsSampler: .mockAny(), core: core)

        // When
        bridge.send(body: 123)

        // Then
        XCTAssertEqual(dd.logger.errorLog?.message, "Encountered an error when receiving web view event")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, #"invalidMessage(description: "123")"#)
        XCTAssertEqual(telemetry.messages.first?.asError?.message, "Encountered an error when receiving web view event - WebViewMessageError does not conform to TelemetrySanitizableError — reporting type name only")
    }
    func testCapturedMessage_preservesCaptureAcrossTransport() throws {
        let owner = RUMContextHandoff.Owner()
        let context = RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: "native-a")
        let capture = RUMContextHandoff.Capture(
            owner: owner,
            value: .init(rumContext: context, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil)
        )
        for eventType in ["rum", "internal_telemetry", "log"] {
            let receiver = FeatureMessageReceiverMock()
            let core = PassthroughCoreMock(messageReceiver: receiver)
            let emitter = MessageEmitter(logsSampler: Sampler(samplingRate: 100), core: core)
            emitter.send(
                body: "{\"eventType\":\"\(eventType)\",\"event\":{\"view\":{\"id\":\"browser-view\"},\"session\":{\"id\":\"browser-session\"}}}",
                slotId: nil,
                capture: capture
            )
            let message = try XCTUnwrap(receiver.messages.firstPayload as? WebViewMessageWithRUMContext)
            XCTAssertTrue(message.capture.owner === owner)
            XCTAssertEqual(message.capture.value.sceneIdentifier, "scene-a")
            XCTAssertEqual(message.capture.value.rumContext?.viewID, "native-a")
            let event: WebViewMessage.Event
            switch message.message {
            case .rum(let value), .telemetry(let value), .log(let value): event = value
            default: return XCTFail("Unexpected message")
            }
            XCTAssertEqual(try JSONObjectMatcher(object: event).value("view.id"), "browser-view")
            XCTAssertEqual(try JSONObjectMatcher(object: event).value("session.id"), "browser-session")
        }
    }

    func testWithoutCapture_preservesLegacyMessageTransport() throws {
        for eventType in ["rum", "internal_telemetry", "log"] {
            let receiver = FeatureMessageReceiverMock()
            let core = PassthroughCoreMock(messageReceiver: receiver)
            let emitter = MessageEmitter(logsSampler: Sampler(samplingRate: 100), core: core)
            emitter.send(body: "{\"eventType\":\"\(eventType)\",\"event\":{\"test\":true}}")
            XCTAssertNotNil(receiver.messages.firstWebViewMessage)
            XCTAssertNil(receiver.messages.firstPayload as? WebViewMessageWithRUMContext)
        }
    }

    func testCapturedRUMAndTelemetryKeepOriginalSamplingAcrossDeferredDelivery() throws {
        for eventType in ["rum", "internal_telemetry"] {
            for keepCapture in [false, true] {
                let owner = RUMContextHandoff.Owner()
                let original = RUMCoreContext(
                    applicationID: "native-app",
                    sessionID: "native-session",
                    sessionSampler: keepCapture ? .mockKeepAll() : .mockRejectAll(),
                    viewID: "native-a"
                )
                let peer = RUMCoreContext(
                    applicationID: "native-app",
                    sessionID: "native-session",
                    sessionSampler: keepCapture ? .mockRejectAll() : .mockKeepAll(),
                    viewID: "native-b"
                )
                let scope = FeatureScopeMock(
                    context: .mockWith(serverTimeOffset: 0, additionalContext: [original]),
                    deferEventWriteContext: true
                )
                let subscriber = RUMCommandSubscriberMock()
                let receiver = WebViewEventReceiver(
                    featureScope: scope,
                    dateProvider: DateProviderMock(),
                    commandSubscriber: subscriber,
                    viewCache: ViewCache(dateProvider: DateProviderMock())
                )
                let core = CapturedProcessingCore(owner: owner, receiver: receiver, scope: scope)
                let emitter = MessageEmitter(logsSampler: .mockKeepAll(), core: core)
                let capture = RUMContextHandoff.Capture(
                    owner: owner,
                    value: .init(
                        rumContext: original,
                        sceneIdentifier: "scene-a",
                        hasPendingUserAction: false,
                        excludedUserActionID: nil
                    )
                )

                emitter.send(
                    body: """
                {"eventType":"\(eventType)","event":{"application":{"id":"browser-app"},"session":{"id":"browser-session"},"view":{"id":"browser-view"},"date":1000000}}
                """,
                slotId: nil,
                capture: capture
            )
                XCTAssertTrue(scope.eventsWritten.isEmpty)
                scope.contextMock = .mockWith(serverTimeOffset: 0, additionalContext: [peer])
                scope.flushDeferredEventWriteContexts()

                XCTAssertEqual(core.receivedMessages, 1)
                XCTAssertEqual(core.sessionChecks, 1)
                XCTAssertEqual(scope.eventsWritten.count, keepCapture ? 1 : 0)
                XCTAssertEqual(subscriber.receivedCommands.count, keepCapture && eventType == "rum" ? 1 : 0)
                if keepCapture {
                    let json = try JSONObjectMatcher(XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first))
                    XCTAssertEqual(try json.value("application.id"), "native-app")
                    XCTAssertEqual(try json.value("session.id"), "native-session")
                    XCTAssertEqual(try json.value("view.id"), "browser-view")
                }
            }
        }
    }

    func testCapturedLogKeepsConfiguredSampling() throws {
        for sampleRate in [Float(0), Float(100)] {
            let receiver = FeatureMessageReceiverMock()
            let core = PassthroughCoreMock()
            core.messageReceiver = receiver
            XCTAssertTrue(receiver.messages.isEmpty)
            let emitter = MessageEmitter(logsSampler: Sampler(samplingRate: sampleRate), core: core)
            let owner = RUMContextHandoff.Owner()
            let capture = RUMContextHandoff.Capture(
                owner: owner,
                value: .init(
                    rumContext: RUMCoreContext(
                        applicationID: "native-app",
                        sessionID: "native-session",
                        sessionSampler: .mockKeepAll(),
                        viewID: "native-a"
                    ),
                    sceneIdentifier: "scene-a",
                    hasPendingUserAction: false,
                    excludedUserActionID: nil
                )
            )

            emitter.send(
                body: "{\"eventType\":\"log\",\"event\":{\"message\":\"browser-log\"}}",
                slotId: nil,
                capture: capture
            )

            XCTAssertNil(receiver.messages.firstWebViewMessage)
            XCTAssertEqual(receiver.messages.count, sampleRate == 0 ? 0 : 1)
            if sampleRate == 0 {
                XCTAssertNil(receiver.messages.firstPayload)
            } else {
                let message = try XCTUnwrap(receiver.messages.firstPayload as? WebViewMessageWithRUMContext)
                XCTAssertTrue(message.capture.owner === owner)
                guard case let .log(event) = message.message else {
                    return XCTFail("Expected captured Browser log")
                }
                XCTAssertEqual(try JSONObjectMatcher(object: event).value("message"), "browser-log")
            }
        }
    }

    func testCapturedRUMKeepsOffsetPerBrowserViewWithoutBorrowingPeerContainer() throws {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_030))
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        cache.insert(id: "native-a-history", timestamp: 1_005_000, hasReplay: true, isActive: false, sceneIdentifier: .init(rawValue: "scene-a"))
        cache.insert(id: "native-a-current", timestamp: 1_020_000, hasReplay: true, isActive: true, sceneIdentifier: .init(rawValue: "scene-a"))
        cache.insert(id: "native-b", timestamp: 1_009_000, hasReplay: true, isActive: true, sceneIdentifier: .init(rawValue: "scene-b"))
        let original = RUMCoreContext(
            applicationID: "native-app",
            sessionID: "native-session",
            sessionSampler: .mockKeepAll(),
            viewID: "native-a-current"
        )
        let peer = RUMCoreContext(
            applicationID: "native-app",
            sessionID: "native-session",
            sessionSampler: .mockKeepAll(),
            viewID: "native-b"
        )
        let scope = FeatureScopeMock(context: .mockWith(serverTimeOffset: 10, additionalContext: [peer]))
        let subscriber = RUMCommandSubscriberMock()
        let receiver = WebViewEventReceiver(
            featureScope: scope,
            dateProvider: clock,
            commandSubscriber: subscriber,
            viewCache: cache
        )
        let owner = RUMContextHandoff.Owner()
        let core = CapturedProcessingCore(owner: owner, receiver: receiver, scope: scope)
        let emitter = MessageEmitter(logsSampler: .mockKeepAll(), core: core)
        let capture = RUMContextHandoff.Capture(
            owner: owner,
            value: .init(
                rumContext: original,
                sceneIdentifier: "scene-a",
                hasPendingUserAction: false,
                excludedUserActionID: nil
            )
        )
        let views = ["browser-one", "browser-one", "browser-two"]
        let dates = [1_000_000, 1_001_000, 1_002_000]
        for index in views.indices {
            if index == 1 {
                let offsets = try XCTUnwrap(scope.contextMock.additionalContext(ofType: RUMWebViewContext.self))
                scope.contextMock = .mockWith(serverTimeOffset: 25, additionalContext: [peer, offsets])
            }
            emitter.send(
                body: """
            {"eventType":"rum","event":{"application":{"id":"browser-app"},"session":{"id":"browser-session"},"view":{"id":"\(views[index])"},"date":\(dates[index]),"container":{"view":{"id":"spoofed-peer"}}}}
            """,
                slotId: nil,
                capture: capture
            )
        }

        let events = scope.eventsWritten(ofType: AnyEncodable.self)
        XCTAssertEqual(events.count, 3)
        guard events.count == 3 else {
            return
        }
        XCTAssertEqual(core.receivedMessages, 3)
        XCTAssertEqual(core.sessionChecks, 3)
        XCTAssertEqual(subscriber.receivedCommands.count, 3)
        let correctedDates: [Int64] = [1_010_000, 1_011_000, 1_027_000]
        let containers = ["native-a-history", "native-a-history", "native-a-current"]
        for (index, event) in events.enumerated() {
            let json = try JSONObjectMatcher(event)
            XCTAssertEqual(try json.value("date"), correctedDates[index])
            XCTAssertEqual(try json.value("view.id"), views[index])
            XCTAssertEqual(try json.value("container.view.id"), containers[index])
            XCTAssertEqual(try json.value("application.id"), "native-app")
            XCTAssertEqual(try json.value("session.id"), "native-session")
        }
    }

    func testCapturedLogKeepsPayloadAndOriginalSampledOwnershipAtDeferredWrite() throws {
        for keepCapture in [false, true] {
            let owner = RUMContextHandoff.Owner()
            let original = RUMCoreContext(
                applicationID: "native-app",
                sessionID: "native-session",
                sessionSampler: keepCapture ? .mockKeepAll() : .mockRejectAll(),
                viewID: "native-a",
                userActionID: "action-a"
            )
            let peer = RUMCoreContext(
                applicationID: "native-app",
                sessionID: "native-session",
                sessionSampler: keepCapture ? .mockRejectAll() : .mockKeepAll(),
                viewID: "native-b",
                userActionID: "action-b"
            )
            let scope = FeatureScopeMock(
                context: .mockWith(serverTimeOffset: 0, additionalContext: [original]),
                deferEventWriteContext: true
            )
            let core = CapturedProcessingCore(owner: owner, receiver: WebViewLogReceiver(), scope: scope)
            let emitter = MessageEmitter(logsSampler: .mockKeepAll(), core: core)
            let capture = RUMContextHandoff.Capture(
                owner: owner,
                value: .init(
                    rumContext: original,
                    sceneIdentifier: "scene-a",
                    hasPendingUserAction: false,
                    excludedUserActionID: nil
                )
            )
            let event = [
                "message": "browser-log",
                LogEvent.Attributes.RUM.applicationID: "spoofed-application",
                LogEvent.Attributes.RUM.sessionID: "spoofed-session",
                LogEvent.Attributes.RUM.viewID: "spoofed-peer",
                LogEvent.Attributes.RUM.actionID: "spoofed-action"
            ]
            let data = try JSONSerialization.data(withJSONObject: ["eventType": "log", "event": event])
            emitter.send(
                body: try XCTUnwrap(String(data: data, encoding: .utf8)),
                slotId: nil,
                capture: capture
            )
            XCTAssertTrue(scope.eventsWritten.isEmpty)
            scope.contextMock = .mockWith(serverTimeOffset: 0, additionalContext: [peer])
            scope.flushDeferredEventWriteContexts()

            XCTAssertEqual(core.receivedMessages, 1)
            XCTAssertEqual(core.sessionChecks, 1)
            XCTAssertEqual(scope.eventsWritten.count, 1)
            let json = try JSONObjectMatcher(XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first))
            XCTAssertEqual(try json.value("message"), "browser-log")
            let expected: [String: String] = keepCapture ? [
                LogEvent.Attributes.RUM.applicationID: "native-app",
                LogEvent.Attributes.RUM.sessionID: "native-session",
                LogEvent.Attributes.RUM.viewID: "native-a",
                LogEvent.Attributes.RUM.actionID: "action-a"
            ] : [:]
            for key in [
                LogEvent.Attributes.RUM.applicationID, LogEvent.Attributes.RUM.sessionID,
                LogEvent.Attributes.RUM.viewID, LogEvent.Attributes.RUM.actionID
            ] {
                XCTAssertEqual(json.object[key] as? String, expected[key])
            }
        }
    }
}

private final class CapturedProcessingCore: DatadogCoreProtocol, RUMContextHandoffOwnerProviding, RUMContextHandoffSessionValidating, @unchecked Sendable {
    let base = PassthroughCoreMock()
    let owner: RUMContextHandoff.Owner
    let receiver: FeatureMessageReceiver
    let featureScope: FeatureScope
    private(set) var receivedMessages = 0
    private(set) var sessionChecks = 0
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
    var remoteConfiguration: RemoteConfiguration? { base.remoteConfiguration }

    init(owner: RUMContextHandoff.Owner, receiver: FeatureMessageReceiver, scope: FeatureScope) {
        self.owner = owner
        self.receiver = receiver
        self.featureScope = scope
    }

    func register<T>(feature: T) throws where T: DatadogFeature {}
    func feature<T>(named name: String, type: T.Type) -> T? {
        name == Feature.rum ? self as? T : nil
    }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature { featureScope }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        receivedMessages += 1
        if !receiver.receive(message: message, from: self) { fallback() }
    }
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
    func isRUMContextHandoffSessionActive(sessionID: String, owner: RUMContextHandoff.Owner) -> Bool {
        sessionChecks += 1
        return owner === self.owner && owner.isValid && sessionID == "native-session"
    }
}
