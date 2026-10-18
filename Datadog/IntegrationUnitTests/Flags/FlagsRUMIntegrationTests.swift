/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
import TestUtilities
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

    private func prepare(multiSceneTracking: Bool = false, clientBeforeRUM: Bool = false) -> FlagsClientProtocol {
        var configuration = RUM.Configuration(applicationID: "test-app-id")
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
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
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
