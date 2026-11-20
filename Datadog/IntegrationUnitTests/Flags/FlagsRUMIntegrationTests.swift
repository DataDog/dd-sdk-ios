/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import UIKit
#endif
@_spi(Internal)
@testable import TestUtilities
@_spi(Internal)
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags
@testable import DatadogRUM

/// Covers integration scenarios between Flags and RUM features.
final class FlagsRUMIntegrationTests: XCTestCase {
    private enum Fixtures {
        static let flagsData = FlagsData(
            flags: [
                "string-flag": .init(
                    allocationKey: "allocation-123",
                    variationKey: "variation-123",
                    variation: .string("red"),
                    reason: "TARGETING_MATCH",
                    doLog: true
                ),
                "boolean-flag": .init(
                    allocationKey: "allocation-124",
                    variationKey: "variation-124",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true
                )
            ],
            context: .init(
                targetingKey: "user-123",
                attributes: ["foo": .string("bar")]
            ),
            date: .mockAny()
        )
    }

    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()

        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
    }

    private func prepare(
        multiSceneTracking: Bool = false,
        clientBeforeRUM: Bool = false,
        configure: (inout RUM.Configuration) -> Void = { _ in }
    ) -> FlagsClientProtocol {
        var configuration = RUM.Configuration(applicationID: "test-app-id")
        configure(&configuration)
        if multiSceneTracking {
            configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
            configuration.featureFlags = [.multiSceneTracking: true]
        }
        if !clientBeforeRUM {
            RUM.enable(with: configuration, in: core)
        }
        Flags.enable(in: core)
        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        featureScope.dataStore.flush()
        let client = FlagsClient.create(in: core)
        featureScope.dataStore.flush()
        if clientBeforeRUM {
            RUM.enable(with: configuration, in: core)
        }
        return client
    }

    override func tearDownWithError() throws {
        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.dataStore.clearAllData()

        try core.flushAndTearDown()
        core = nil

        super.tearDown()
    }

    func testFirstFlagsOnlyTracksTheFlagExplicitlyEvaluatedByTheHandler() throws {
        let core = self.core!
        let client = prepare()
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "first-flags", name: "First Flags")
        let delivered = expectation(description: "first flags")
        client.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged.sorted(), ["boolean-flag", "string-flag"])
            XCTAssertEqual(FlagsClient.shared(in: core).getBooleanValue(key: "boolean-flag", defaultValue: false), true)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        client.onFirstFlags { _ in }
        core.flush()
        monitor.stopView(key: "first-flags")
        let session = try XCTUnwrap(RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers()).first)
        let view = try XCTUnwrap(session.views.first { $0.name == "First Flags" })
        let flags = try XCTUnwrap(view.latestViewEvent?.featureFlags?.featureFlagsInfo)
        XCTAssertEqual(flags.count, 1)
        XCTAssertNotNil(flags["boolean-flag"])
        XCTAssertNil(flags["string-flag"])
    }

    func testWhenFlagIsEvaluated_itAddsFeatureFlagToRUMView() throws {
        // Given
        let client = prepare()
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "test-view", name: "Test View")

        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.dataStore.flush()

        let boolValue = client.getBooleanValue(key: "boolean-flag", defaultValue: false)
        let stringValue = client.getStringValue(key: "string-flag", defaultValue: "blue")
        XCTAssertTrue(boolValue)
        XCTAssertEqual(stringValue, "red")

        core.flush()

        monitor.stopView(key: "test-view")

        // Then
        let session = try XCTUnwrap(
            RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers()).first
        )
        let view = try XCTUnwrap(session.views.first { $0.name == "Test View" })
        let featureFlags = try XCTUnwrap(
            view.latestViewEvent?.featureFlags?.featureFlagsInfo,
            "View should have feature flags"
        )

        XCTAssertEqual(featureFlags.count, 2)
        XCTAssertEqual((featureFlags["boolean-flag"] as? AnyCodable)?.value as? String, "variation-124")
        XCTAssertEqual((featureFlags["string-flag"] as? AnyCodable)?.value as? String, "variation-123")
    }

    #if os(iOS)
    func testReadyClientCreatedBeforeRUMKeepsSceneOwnershipAndValues() throws {
        try requireMultiSceneRuntime()
        try assertReadyClientOwnership(createdBeforeRUM: true)
    }

    func testReadyClientCreatedAfterRUMKeepsSceneOwnershipAndValues() throws {
        try requireMultiSceneRuntime()
        try assertReadyClientOwnership(createdBeforeRUM: false)
    }

    func testReadyClientDoesNotReattributeStaleCaptures() throws {
        try requireMultiSceneRuntime()
        let client = prepare(multiSceneTracking: true)
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let owner = try XCTUnwrap(core.rumContextHandoffOwner)
        XCTAssertTrue(monitor.rumContextHandoffOwner === owner)
        let originalScene = RUMSceneIdentifier(rawValue: "original")
        let peerScene = RUMSceneIdentifier(rawValue: "peer")
        startView("original", in: originalScene, monitor: monitor)
        startView("peer", in: peerScene, monitor: monitor)
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(originalScene)))
        let captured = executionValue(original, scene: originalScene)

        XCTAssertTrue(RUMContextHandoff.withValue(captured, for: owner) {
            client.getBooleanValue(key: "boolean-flag", defaultValue: false)
        })
        core.flush()
        monitor.process(command: RUMStopViewCommand(
            target: .scene(originalScene), time: Date(), attributes: [:], identity: ViewIdentifier("original")
        ))
        core.flush()
        XCTAssertEqual(RUMContextHandoff.withValue(captured, for: owner) {
            client.getStringValue(key: "string-flag", defaultValue: "blue")
        }, "red")
        core.flush()

        let peer = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene)))
        let sessionCapture = executionValue(peer, scene: peerScene)
        monitor.stopSession()
        core.flush()
        startView("replacement", in: peerScene, monitor: monitor)
        let replacement = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene)))
        XCTAssertNotEqual(peer.sessionID, replacement.sessionID)
        XCTAssertEqual(RUMContextHandoff.withValue(sessionCapture, for: owner) {
            client.getStringValue(key: "string-flag", defaultValue: "blue")
        }, "red")
        core.flush()

        let ownerCapture = executionValue(replacement, scene: peerScene)
        owner.invalidate()
        XCTAssertFalse(owner.isValid)
        XCTAssertEqual(RUMContextHandoff.withValue(ownerCapture, for: owner) {
            client.getStringValue(key: "string-flag", defaultValue: "blue")
        }, "red")
        core.flush()
        let sessions = try RUMSessionMatcher.groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
        let views = sessions.flatMap(\.views)
        let originalView = try XCTUnwrap(views.first { $0.viewID == original.viewID })
        XCTAssertEqual(flag("boolean-flag", in: originalView), "variation-124")
        XCTAssertNotNil(views.first { $0.viewID == replacement.viewID })
        for view in views {
            XCTAssertNil(flag("string-flag", in: view), "Stale evaluation leaked into \(view.name ?? view.viewID)")
            if view.viewID != original.viewID {
                XCTAssertNil(flag("boolean-flag", in: view))
            }
        }
    }

    @MainActor
    func testFirstAutomaticTapAfterTimeoutKeepsFlagOnRestoredView() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Automatic scene actions require iOS 27.") }
        let date = Date()
        let wallClock = DateProviderMock(now: date)
        let monotonicClock = MonotonicClockMock(elapsedTime: 123)
        let client = prepare(multiSceneTracking: true) {
            $0.dateProvider = wallClock
            $0.monotonicClock = monotonicClock
        }
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let owner = try XCTUnwrap(core.rumContextHandoffOwner)
        let tappedScene = RUMSceneIdentifier(rawValue: "tapped")
        let peerScene = RUMSceneIdentifier(rawValue: "peer")
        startView("tapped", in: tappedScene, monitor: monitor)
        startView("peer", in: peerScene, monitor: monitor)
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(tappedScene)))
        let peer = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene)))
        XCTAssertEqual(original.sessionID, peer.sessionID)

        XCTAssertEqual(RUMContextHandoff.withValue(executionValue(peer, scene: peerScene), for: owner) {
            client.getStringValue(key: "string-flag", defaultValue: "blue")
        }, "red")
        core.flush()

        let window = UIWindow(frame: .zero)
        let button = UIButton()
        button.accessibilityIdentifier = "FlagAfterTimeout"
        window.addSubview(button)
        let factory = UITouchCommandFactory(
            dateProvider: wallClock,
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(),
            uiKitPredicate: DefaultUIKitRUMActionsPredicate(),
            swiftUIPredicate: nil,
            swiftUIDetector: nil
        )
        let handler = RUMSceneActionsHandler(
            legacyHandler: RUMActionsHandler(dateProvider: wallClock, eventCommandsFactory: factory),
            eventCommandsFactory: factory,
            dateProvider: wallClock,
            owner: owner,
            expectedMonitor: monitor,
            sceneIdentifier: { $0 === window ? tappedScene : nil }
        )
        handler.publish(to: monitor)

        let timeout = RUMSessionScope.Constants.sessionTimeoutDuration
        wallClock.now.addTimeInterval(timeout)
        monotonicClock.advance(by: timeout)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(tappedScene)))
        handler.intercept(application: .shared, event: .mockWith(touch: .mockWith(view: button))) {
            let callback = RUMContextHandoff.current(for: owner)
            XCTAssertEqual(callback?.sceneIdentifier, tappedScene.rawValue)
            XCTAssertEqual(callback?.hasPendingUserAction, true)
            XCTAssertTrue(client.getBooleanValue(key: "boolean-flag", defaultValue: false))
        }

        core.flush()
        let restored = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(tappedScene)))
        XCTAssertNotEqual(restored.sessionID, original.sessionID)
        XCTAssertNotEqual(restored.viewID, original.viewID)
        XCTAssertNotNil(restored.userActionID)
        monitor.process(command: RUMStopViewCommand(
            target: .scene(tappedScene), time: wallClock.now, attributes: [:], identity: ViewIdentifier("tapped")
        ))
        let evaluations = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(evaluations.map { $0.flag.key }.sorted(), ["boolean-flag", "string-flag"])
        // Keep incremental view writes. SDK telemetry shares this stream and has no session ID.
        let rumEvents = try core.waitAndReturnRUMEventMatchers().filter { event in
            let type = try event.eventType()
            return type == "view" || type == "view_update" || type == "action"
        }
        let sessions = try RUMSessionMatcher.groupMatchersBySessions(rumEvents)
        let views = sessions.flatMap(\.views)
        let restoredView = try XCTUnwrap(views.first { $0.viewID == restored.viewID })
        let peerView = try XCTUnwrap(views.first { $0.viewID == peer.viewID })
        let resumedSession = try XCTUnwrap(sessions.first { $0.sessionID == restored.sessionID })
        let tap = try XCTUnwrap(resumedSession.actionEvents.first { $0.action.target?.name == "UIButton(FlagAfterTimeout)" })
        XCTAssertEqual(tap.view.id, restored.viewID)
        XCTAssertEqual(flag("string-flag", in: peerView), "variation-123")
        XCTAssertTrue(views.filter { $0.viewID != restored.viewID }.allSatisfy { flag("boolean-flag", in: $0) == nil })
        XCTAssertEqual(flag("boolean-flag", in: restoredView), "variation-124", "First automatic tap lost its flag on the restored view")
    }

    func testRolloverReceiptRejectsWrongPredecessorAndWrongAcceptedView() throws {
        try requireMultiSceneRuntime()
        _ = prepare(multiSceneTracking: true)
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let owner = try XCTUnwrap(core.rumContextHandoffOwner)
        let originalScene = RUMSceneIdentifier(rawValue: "original")
        let peerScene = RUMSceneIdentifier(rawValue: "peer")
        startView("original", in: originalScene, monitor: monitor)
        startView("peer", in: peerScene, monitor: monitor)
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(originalScene)))
        let peer = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene)))
        let originalViewID = try XCTUnwrap(original.viewID)
        let peerViewID = try XCTUnwrap(peer.viewID)
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: nil, rolloverSource: original)

        receipt.prepareRestoredView(
            fromSessionID: peer.sessionID, fromViewID: peerViewID, sessionID: "renewed", viewID: "restored-peer"
        )
        receipt.prepareRestoredView(
            fromSessionID: original.sessionID, fromViewID: originalViewID, sessionID: "renewed", viewID: "restored-original"
        )
        XCTAssertNil(receipt.restoredView(for: owner))
        receipt.accept(sessionID: "renewed", viewID: "restored-peer", actionID: "peer-tap")
        XCTAssertNil(receipt.restoredView(for: owner))
        receipt.accept(sessionID: "renewed", viewID: "restored-original", actionID: "later-tap")
        XCTAssertNil(receipt.restoredView(for: owner))
    }

    private func requireMultiSceneRuntime() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Captured scene ownership requires iOS 27.")
        }
    }

    private func assertReadyClientOwnership(createdBeforeRUM: Bool) throws {
        let client = prepare(multiSceneTracking: true, clientBeforeRUM: createdBeforeRUM)
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let owner = try XCTUnwrap(core.rumContextHandoffOwner)
        XCTAssertTrue(monitor.rumContextHandoffOwner === owner)
        XCTAssertTrue(owner.isValid)
        let firstScene = RUMSceneIdentifier(rawValue: "first")
        let secondScene = RUMSceneIdentifier(rawValue: "second")
        startView("first", in: firstScene, monitor: monitor)
        startView("second", in: secondScene, monitor: monitor)
        let first = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(firstScene)))
        let second = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(secondScene)))
        XCTAssertEqual(first.sessionID, second.sessionID)
        XCTAssertNotEqual(first.viewID, second.viewID)

        let details = RUMContextHandoff.withValue(executionValue(first, scene: firstScene), for: owner) {
            client.getDetails(key: "boolean-flag", defaultValue: false)
        }
        XCTAssertTrue(details.value)
        XCTAssertEqual(details.variant, "variation-124")
        XCTAssertEqual(details.reason, "CACHED")
        XCTAssertEqual(details.allocationKey, "allocation-124")
        XCTAssertNil(details.error)
        XCTAssertEqual(RUMContextHandoff.withValue(executionValue(second, scene: secondScene), for: owner) {
            client.getStringValue(key: "string-flag", defaultValue: "blue")
        }, "red")
        XCTAssertTrue(client.getBooleanValue(key: "missing-flag", defaultValue: true))
        let internalClient = try XCTUnwrap(client as? FlagsClientInternal)
        let assignment = try XCTUnwrap(Fixtures.flagsData.flags["string-flag"])
        RUMContextHandoff.withValue(executionValue(first, scene: firstScene), for: owner) {
            internalClient.sendFlagEvaluation(key: "internal-flag", assignment: assignment, context: Fixtures.flagsData.context)
        }
        core.flush()
        let evaluations = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(evaluations.map { $0.flag.key }.sorted(), ["boolean-flag", "internal-flag", "missing-flag", "string-flag"])

        let sessions = try RUMSessionMatcher.groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
        let session = try XCTUnwrap(sessions.first { $0.sessionID == first.sessionID })
        let firstView = try XCTUnwrap(session.views.first { $0.viewID == first.viewID })
        let secondView = try XCTUnwrap(session.views.first { $0.viewID == second.viewID })
        XCTAssertEqual(flag("boolean-flag", in: firstView), "variation-124")
        XCTAssertNil(flag("string-flag", in: firstView))
        XCTAssertEqual(flag("internal-flag", in: firstView), "variation-123")
        XCTAssertEqual(flag("string-flag", in: secondView), "variation-123")
        XCTAssertNil(flag("internal-flag", in: secondView))
        XCTAssertNil(flag("boolean-flag", in: secondView))
        for view in session.views {
            XCTAssertNil(flag("missing-flag", in: view))
        }
    }

    private func startView(_ name: String, in scene: RUMSceneIdentifier, monitor: Monitor) {
        monitor.process(command: RUMStartViewCommand(
            time: Date(),
            identity: ViewIdentifier(name),
            name: name,
            path: name,
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual,
            target: .scene(scene)
        ))
        core.flush()
    }

    private func executionValue(_ context: RUMCoreContext, scene: RUMSceneIdentifier) -> RUMContextHandoff.CurrentValue {
        .init(rumContext: context, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil)
    }

    private func flag(_ key: String, in view: RUMSessionMatcher.View) -> String? {
        (view.latestViewEvent?.featureFlags?.featureFlagsInfo[key] as? AnyCodable)?.value as? String
    }
    #endif
}
