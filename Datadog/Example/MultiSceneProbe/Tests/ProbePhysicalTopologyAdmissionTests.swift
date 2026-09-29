/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import XCTest

@MainActor
final class ProbePhysicalTopologyAdmissionTests: XCTestCase {
    private func scenes() -> [ProbePhysicalSceneObservation] {
        ["scene-A", "scene-B"].enumerated().map { index, name in
            .init(logicalSceneID: name, nativeSceneID: "native-" + name, generation: 0,
                  connected: true, activationState: index == 0 ? "foreground-inactive" : "foreground-active",
                  hidden: false, alpha: 1, geometry: .init(x: Double(index) * 400, y: 0, width: 400, height: 800))
        }
    }

    private func challenge(_ live: [ProbePhysicalSceneObservation]? = nil) -> ProbePhysicalAdmissionChallenge {
        .init(runID: "exp196-test", scenarioID: ProbePhysicalTopologyAdmission.scenarioID,
              processID: 123, nonce: "fresh-nonce", createdAtMilliseconds: 1_000,
              observedAtMilliseconds: 1_500, scenes: live ?? scenes())
    }

    private func receipt() -> ProbePhysicalAdmissionReceipt {
        .init(runID: "exp196-test", scenarioID: ProbePhysicalTopologyAdmission.scenarioID,
              processID: 123, nonce: "fresh-nonce", capturedAtMilliseconds: 1_600,
              captureID: "00000000-0000-0000-0000-000000000001",
              evidenceSHA256: String(repeating: "a", count: 64),
              nativeSceneIDs: ["scene-A": "native-scene-A", "scene-B": "native-scene-B"],
              generations: ["scene-A": 0, "scene-B": 0])
    }

    func testAcceptsOnlyFreshExactReceiptAndLiveNativePair() {
        XCTAssertNil(ProbePhysicalTopologyAdmission.validate(receipt(), challenge: challenge(), live: scenes(), now: 2_000))
    }

    func testRejectsStaleIdentityAndDisplayEvidence() {
        for name in ["run", "scenario", "process", "nonce", "early", "old", "future", "capture", "hash", "native", "generation", "extra"] {
            var value = receipt()
            var now: Int64 = 2_000
            switch name {
            case "run": value.runID = "old"
            case "scenario": value.scenarioID = "old"
            case "process": value.processID = 124
            case "nonce": value.nonce = "old"
            case "early": value.capturedAtMilliseconds = 999
            case "old": now = 61_601
            case "future": value.capturedAtMilliseconds = 4_001
            case "capture": value.captureID = ""
            case "hash": value.evidenceSHA256 = String(repeating: "z", count: 64)
            case "native": value.nativeSceneIDs["scene-A"] = "native-scene-B"
            case "generation": value.generations["scene-A"] = 1
            case "extra": value.nativeSceneIDs["scene-C"] = "foreign"
            default: XCTFail("unknown case")
            }
            XCTAssertNotNil(ProbePhysicalTopologyAdmission.validate(value, challenge: challenge(), live: scenes(), now: now), name)
        }
    }

    func testRejectsHiddenBackgroundDetachedAliasedAndChangedScenes() throws {
        for (field, bad) in [("hidden", true as Any), ("alpha", 0), ("connected", false),
                             ("activationState", "background"), ("activationState", "unattached"),
                             ("nativeSceneID", "native-scene-B"), ("generation", 1)] {
            var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scenes())) as? [[String: Any]])
            rows[0][field] = bad
            let live = try JSONDecoder().decode([ProbePhysicalSceneObservation].self,
                                               from: JSONSerialization.data(withJSONObject: rows))
            XCTAssertNotNil(ProbePhysicalTopologyAdmission.validate(receipt(), challenge: challenge(), live: live, now: 2_000), field)
        }
        XCTAssertNotNil(ProbePhysicalTopologyAdmission.validateLive(Array(scenes().prefix(1))))
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scenes())) as? [[String: Any]])
        rows[0]["geometry"] = ["x": 0, "y": 0, "width": 0, "height": 800]
        let zero = try JSONDecoder().decode([ProbePhysicalSceneObservation].self,
                                           from: JSONSerialization.data(withJSONObject: rows))
        XCTAssertNotNil(ProbePhysicalTopologyAdmission.validateLive(zero))
    }

    func testReceiptCannotAdoptAReplacementSinceChallenge() throws {
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scenes())) as? [[String: Any]])
        rows[0]["nativeSceneID"] = "reconnected-A"
        rows[0]["generation"] = 1
        let changed = try JSONDecoder().decode([ProbePhysicalSceneObservation].self,
                                              from: JSONSerialization.data(withJSONObject: rows))
        var value = receipt()
        value.nativeSceneIDs["scene-A"] = "reconnected-A"
        value.generations["scene-A"] = 1
        XCTAssertNotNil(ProbePhysicalTopologyAdmission.validate(value, challenge: challenge(), live: changed, now: 2_000))
    }

    func testDriverNeverExecutesMutationWhenPrecriticalAdmissionFails() async throws {
        let scenario = ProbeScenario(identifier: "admission-test", trackingMode: .automatic, layout: .stack,
                                     steps: [.init(.startKeyedManualView, scene: "scene-A", value: "compose")],
                                     completionConditions: [], expectedSemanticTimeline: [])
        let recorder = ProbeEventRecorder(runID: "test", scenarioID: scenario.identifier, sink: { _ in })
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        guard case .registered(let handle) = registry.register(logicalSceneID: "scene-A", nativeSceneID: "native-A",
                                                               window: window, currentRoute: ["home"]) else {
            return XCTFail("registration")
        }
        let executor = ProbeSceneStepExecutor()
        var calls = 0
        executor.configure(handle: handle) { _ in calls += 1; return .accepted }
        let driver = ProbeScenarioDriver(scenario: scenario, recorder: recorder, sceneRegistry: registry,
                                         stepAdmission: { _, _, _ in "hidden peer" })
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()
        let result = await driver.waitUntilFinished()
        XCTAssertEqual(result?.state, .inconclusive)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(recorder.snapshot().contains { $0.kind == .stepAcknowledged })
    }

    func testTopologySurvivesSignalEnvelopeAndCodableRoundTrip() throws {
        let observation = ProbePhysicalTopologyObservation(nonce: "fresh", captureID: receipt().captureID,
                                                           evidenceSHA256: receipt().evidenceSHA256, scenes: scenes())
        let signal = ProbeSignal(kind: .assertion, name: "before", physicalTopology: observation)
            .enveloped(sequence: 1, timestampMilliseconds: 2_000, runID: "exp196-test",
                       scenarioID: ProbePhysicalTopologyAdmission.scenarioID)
        let decoded = try JSONDecoder().decode(ProbeSignal.self, from: JSONEncoder().encode(signal))
        XCTAssertEqual(decoded.physicalTopology, observation)
        XCTAssertEqual(decoded.runID, "exp196-test")
    }
}


@MainActor
final class ProbePhysicalOperationProfileTests: XCTestCase {
    private let revision = String(repeating: "a", count: 40)

    private func scenario() throws -> ProbeScenario {
        try XCTUnwrap(ProbeScenarioCatalog.all.first { $0.identifier == ProbePhysicalOperationProfile.scenarioID })
    }

    private func profile() throws -> ProbePhysicalOperationProfile {
        try XCTUnwrap(ProbePhysicalOperationProfile.make(scenario: scenario(), sourceRevision: revision, buildConfiguration: "Debug"))
    }

    private func scenes() -> [ProbePhysicalSceneObservation] {
        ["scene-A", "scene-B"].enumerated().map { index, name in
            .init(logicalSceneID: name, nativeSceneID: "native-" + name, generation: 0,
                  connected: true, activationState: index == 0 ? "foreground-inactive" : "foreground-active",
                  hidden: false, alpha: 1, geometry: .init(x: Double(index) * 400, y: 0, width: 400, height: 800),
                  windowIdentity: "window-" + name, rootIdentity: "root-" + name)
        }
    }

    private func changedScenes(_ key: String, _ value: Any) throws -> [ProbePhysicalSceneObservation] {
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scenes())) as? [[String: Any]])
        rows[0][key] = value
        return try JSONDecoder().decode([ProbePhysicalSceneObservation].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private func challenge() -> ProbePhysicalAdmissionChallenge {
        .init(runID: "operation-test", scenarioID: ProbePhysicalOperationProfile.scenarioID,
              processID: 123, nonce: "fresh", createdAtMilliseconds: 1_000, observedAtMilliseconds: 1_500, scenes: scenes())
    }

    private func receipt() throws -> ProbePhysicalOperationReceipt {
        .init(topology: .init(runID: "operation-test", scenarioID: ProbePhysicalOperationProfile.scenarioID,
                             processID: 123, nonce: "fresh", capturedAtMilliseconds: 1_600,
                             captureID: "00000000-0000-0000-0000-000000000001", evidenceSHA256: String(repeating: "b", count: 64),
                             nativeSceneIDs: ["scene-A": "native-scene-A", "scene-B": "native-scene-B"],
                             generations: ["scene-A": 0, "scene-B": 0]),
              profile: try profile(), owners: try XCTUnwrap(ProbePhysicalOperationProfile.ownerIdentities(scenes())))
    }

    func testProfileMatchesActualCatalogAndHasSeparateReceiptNamespace() throws {
        let value = try profile()
        XCTAssertEqual(try scenario().steps, ProbePhysicalOperationProfile.steps)
        XCTAssertEqual(ProbePhysicalOperationProfile.criticalInterval, 6...21)
        XCTAssertEqual(value.scenarioSHA256.count, 64)
        XCTAssertEqual(value, try profile())
        XCTAssertEqual(value.inference, "debug-rum-ui-event-network-context")
        XCTAssertEqual(ProbePhysicalOperationProfile.receiptSuffix, ".operations-physical-admission.json")
        XCTAssertNotEqual(ProbePhysicalOperationProfile.scenarioID, ProbePhysicalTopologyAdmission.scenarioID)
    }

    func testUnknownScenarioSourceReleaseAndChangedStepContractAreRejected() throws {
        let original = try scenario()
        XCTAssertNil(ProbePhysicalOperationProfile.make(scenario: original, sourceRevision: revision, buildConfiguration: "Release"))
        XCTAssertNil(ProbePhysicalOperationProfile.make(scenario: original, sourceRevision: "unfrozen", buildConfiguration: "Debug"))
        let data = try JSONEncoder().encode(original)
        for field in ["identifier", "steps", "initialWindows", "trackingMode", "layout", "requiredCapabilities"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            switch field {
            case "identifier": value[field] = ProbePhysicalTopologyAdmission.scenarioID
            case "steps":
                var steps = try XCTUnwrap(value[field] as? [[String: Any]])
                steps.swapAt(18, 20)
                value[field] = steps
            case "initialWindows": value[field] = ["scene-B", "scene-A"]
            case "trackingMode": value[field] = "automatic"
            case "layout": value[field] = "split-selection"
            default: value[field] = []
            }
            let changed = try JSONDecoder().decode(ProbeScenario.self, from: JSONSerialization.data(withJSONObject: value))
            XCTAssertNil(ProbePhysicalOperationProfile.make(scenario: changed, sourceRevision: revision, buildConfiguration: "Debug"), field)
        }
    }

    func testRejectsChangedCompletionTimelineAndRuntimeOptions() throws {
        let original = try scenario()
        for field in ["completionConditions", "expectedSemanticTimeline", "runtimeOptions"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            if field == "runtimeOptions" {
                var options = try XCTUnwrap(value[field] as? [String: Any])
                options["automaticallyClosesSceneB"] = true
                value[field] = options
            } else { value[field] = [] }
            let changed = try JSONDecoder().decode(ProbeScenario.self, from: JSONSerialization.data(withJSONObject: value))
            XCTAssertNil(ProbePhysicalOperationProfile.make(scenario: changed, sourceRevision: revision, buildConfiguration: "Debug"), field)
        }
    }

    func testReceiptDecodingRejectsMalformedMissingAndUnknownFields() throws {
        let raw = try JSONEncoder().encode(receipt())
        let decoded = try JSONDecoder().decode(ProbePhysicalOperationReceipt.self, from: raw)
        XCTAssertNil(try decoded.validate(profile: profile(), challenge: challenge(), live: scenes(), now: 2_000))
        for bytes in [Data(raw.dropLast()), Data("not JSON".utf8), Data("null".utf8)] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProbePhysicalOperationReceipt.self, from: bytes))
        }
        for field in ["topology", "profile", "owners", "extra", "extraTopology", "extraProfile", "missingNested"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            switch field {
            case "topology", "profile", "owners": value.removeValue(forKey: field)
            case "extra": value[field] = "unreviewed"
            default:
                let nested = field == "extraProfile" ? "profile" : "topology"
                var object = try XCTUnwrap(value[nested] as? [String: Any])
                if field == "missingNested" { object.removeValue(forKey: "nonce") }
                else { object["unreviewed"] = true }
                value[nested] = object
            }
            let bytes = try JSONSerialization.data(withJSONObject: value)
            XCTAssertThrowsError(try JSONDecoder().decode(ProbePhysicalOperationReceipt.self, from: bytes), field)
        }
    }

    func testEveryOperationAndFinalMarkerRequiresBeforeAndAfterOwnership() throws {
        var progress = try XCTUnwrap(ProbePhysicalOperationProfile.Progress(scenes: scenes()))
        for index in ProbePhysicalOperationProfile.criticalInterval {
            for after in [false, true] {
                XCTAssertFalse(progress.complete)
                XCTAssertNil(progress.check(index: index, step: ProbePhysicalOperationProfile.steps[index], after: after, scenes: scenes()))
            }
        }
        XCTAssertTrue(progress.complete)
        XCTAssertNotNil(progress.check(index: 21, step: ProbePhysicalOperationProfile.steps[21], after: true, scenes: scenes()))
    }

    func testSkippedDuplicateLateAndWrongStepFailPermanently() throws {
        for (index, after) in [(7, false), (6, true), (5, false), (22, false)] {
            var progress = try XCTUnwrap(ProbePhysicalOperationProfile.Progress(scenes: scenes()))
            XCTAssertNotNil(progress.check(index: index, step: ProbePhysicalOperationProfile.steps[6], after: after, scenes: scenes()))
            XCTAssertNotNil(progress.check(index: 6, step: ProbePhysicalOperationProfile.steps[6], after: false, scenes: scenes()))
        }
        var progress = try XCTUnwrap(ProbePhysicalOperationProfile.Progress(scenes: scenes()))
        XCTAssertNotNil(progress.check(index: 6, step: ProbePhysicalOperationProfile.steps[8], after: false, scenes: scenes()))
        var duplicate = try XCTUnwrap(ProbePhysicalOperationProfile.Progress(scenes: scenes()))
        XCTAssertNil(duplicate.check(index: 6, step: ProbePhysicalOperationProfile.steps[6], after: false, scenes: scenes()))
        XCTAssertNotNil(duplicate.check(index: 6, step: ProbePhysicalOperationProfile.steps[6], after: false, scenes: scenes()))
    }

    func testTransientSceneWindowRootAndGenerationDriftCannotBeHiddenByRecovery() throws {
        for (field, value) in [("nativeSceneID", "replaced" as Any), ("generation", 1),
                               ("windowIdentity", "replacement"), ("rootIdentity", "replacement"),
                               ("hidden", true), ("connected", false), ("activationState", "background")] {
            var progress = try XCTUnwrap(ProbePhysicalOperationProfile.Progress(scenes: scenes()))
            XCTAssertNotNil(progress.observe(try changedScenes(field, value)), field)
            XCTAssertNotNil(progress.observe(scenes()), field)
        }
    }

    func testMissingOrAliasedNativeOwnersCannotStartProgress() throws {
        for (field, value) in [("windowIdentity", ""), ("rootIdentity", ""),
                               ("windowIdentity", "window-scene-B"), ("rootIdentity", "root-scene-B"),
                               ("nativeSceneID", "native-scene-B"), ("logicalSceneID", "scene-B")] {
            XCTAssertNil(ProbePhysicalOperationProfile.Progress(scenes: try changedScenes(field, value)), field)
        }
    }

    func testReceiptBindsRunProcessNonceCaptureAndExactProfile() throws {
        let expected = try profile()
        XCTAssertNil(try receipt().validate(profile: expected, challenge: challenge(), live: scenes(), now: 2_000))
        for field in ["run", "process", "nonce", "scenario", "capture", "digest", "early", "source", "configuration", "inference", "steps"] {
            var value = try receipt()
            switch field {
            case "run": value.topology.runID = "old"
            case "process": value.topology.processID = 124
            case "nonce": value.topology.nonce = "old"
            case "scenario": value.topology.scenarioID = ProbePhysicalTopologyAdmission.scenarioID
            case "capture": value.topology.captureID = "missing"
            case "digest": value.topology.evidenceSHA256 = "missing"
            case "early": value.topology.capturedAtMilliseconds = 999
            default:
                value.profile = .init(sourceRevision: field == "source" ? String(repeating: "c", count: 40) : expected.sourceRevision,
                                      buildConfiguration: field == "configuration" ? "Release" : expected.buildConfiguration,
                                      scenarioSHA256: field == "steps" ? String(repeating: "d", count: 64) : expected.scenarioSHA256,
                                      inference: field == "inference" ? "explicit-target" : expected.inference)
            }
            XCTAssertNotNil(value.validate(profile: expected, challenge: challenge(), live: scenes(), now: 2_000), field)
        }
    }

    func testReceiptCannotAdoptReplacedNativeOwner() throws {
        for key in ["windowIdentity", "rootIdentity"] {
            let changed = try changedScenes(key, "replacement")
            var value = try receipt()
            value.owners = try XCTUnwrap(ProbePhysicalOperationProfile.ownerIdentities(changed))
            XCTAssertNotNil(try receipt().validate(profile: profile(), challenge: challenge(), live: changed, now: 2_000))
            XCTAssertNotNil(value.validate(profile: try profile(), challenge: challenge(), live: changed, now: 2_000))
        }
    }
}


@MainActor
final class ProbePhysicalInputTests: XCTestCase {
    private func snapshot() -> ProbePhysicalInputSnapshot {
        let scenes: [ProbePhysicalSceneObservation] = ["scene-A", "scene-B"].enumerated().map { index, label in
            .init(logicalSceneID: label, nativeSceneID: "native-" + label, generation: 0, connected: true,
                  activationState: index == 0 ? "foreground-inactive" : "foreground-active", hidden: false, alpha: 1,
                  geometry: .init(x: Double(index) * 400, y: 0, width: 400, height: 800),
                  windowIdentity: "window-" + label, rootIdentity: "root-" + label)
        }
        let input = scenes.map { row in
            ProbePhysicalInputWindow(logicalSceneID: row.logicalSceneID, nativeSceneID: row.nativeSceneID, generation: 0,
                windowIdentity: row.windowIdentity!, rootIdentity: row.rootIdentity!, observerIdentity: "observer-" + row.logicalSceneID,
                attached: true, enabled: true, reliable: true, touches: 0, revision: 10, mounted: true, transitioning: false, resizing: false)
        }
        let inventory = scenes.map { row in
            ProbePhysicalSceneInventory(nativeSceneID: row.nativeSceneID, activationState: row.activationState,
                keyWindowIdentity: row.windowIdentity, geometry: row.geometry, screenGeometry: .init(x: 0, y: 0, width: 800, height: 800),
                windows: [.init(identity: row.windowIdentity!, rootIdentity: row.rootIdentity, fixtureOwner: row.logicalSceneID,
                                sceneMatches: true, key: true, hidden: false, alpha: 1, mounted: true, geometry: row.geometry)])
        }
        return .init(scenes: scenes, input: input, connectedSceneIDs: scenes.map(\.nativeSceneID),
                     applicationActive: true, inventory: inventory, failure: nil)
    }
    private func edited(_ change: (inout [String: Any]) -> Void) throws -> ProbePhysicalInputSnapshot {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot())) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(ProbePhysicalInputSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func input(_ key: String, _ value: Any) throws -> ProbePhysicalInputSnapshot {
        try edited { object in
            var rows = object["input"] as! [[String: Any]]
            rows[0][key] = value; object["input"] = rows
        }
    }
    private func profile() throws -> ProbePhysicalOperationProfile {
        let scenario = try XCTUnwrap(ProbeScenarioCatalog.all.first { $0.identifier == ProbePhysicalOperationProfile.scenarioID })
        return try XCTUnwrap(ProbePhysicalOperationProfile.make(scenario: scenario,
                              sourceRevision: String(repeating: "a", count: 40), buildConfiguration: "Debug"))
    }
    private func request(phase: String = "setup") throws -> Data {
        try JSONEncoder().encode(ProbePhysicalInputRequest(runID: "input-test", processID: 123, profile: profile(),
                                                        phase: phase, nonce: UUID().uuidString))
    }
    private func exchange() throws -> ProbePhysicalInputExchange {
        try .init(runID: "input-test", processID: 123, profile: profile())
    }
    private func registered() throws -> (ProbeSceneRegistry, UIWindow, ProbeSceneHandle) {
        let registry = ProbeSceneRegistry(), window = UIWindow()
        window.rootViewController = UIViewController()
        guard case .registered(let handle) = registry.register(logicalSceneID: "scene-A", nativeSceneID: "native-scene-A",
                                                               window: window, currentRoute: ["home"]) else {
            throw CocoaError(.coderInvalidValue)
        }
        return (registry, window, handle)
    }

    func testContactLedgerTracksMultipleContactsAndBothTerminalCallbacks() {
        let a = NSObject(), b = NSObject()
        let first = Set([ObjectIdentifier(a)]), second = Set([ObjectIdentifier(b)])
        var ledger = ProbePhysicalContactLedger()
        ledger.began(first); ledger.began(second); ledger.moved(first)
        XCTAssertEqual(ledger.active.count, 2)
        ledger.ended(second); XCTAssertEqual(ledger.active, first)
        ledger.ended(first); ledger.reset()
        XCTAssertTrue(ledger.active.isEmpty); XCTAssertTrue(ledger.reliable); XCTAssertEqual(ledger.revision, 5)
    }

    func testLostDuplicateUnknownAndResetContactsRemainInvalid() {
        let contact = NSObject(), unknown = NSObject()
        let ids = Set([ObjectIdentifier(unknown)])
        let actual = Set([ObjectIdentifier(contact)])
        for mode in ["duplicate", "unknown", "reset", "disabled"] {
            var ledger = ProbePhysicalContactLedger()
            ledger.began(actual)
            switch mode {
            case "duplicate": ledger.began(actual)
            case "unknown": ledger.moved(ids)
            case "reset": ledger.reset()
            default: ledger.invalidate()
            }
            ledger.ended(actual)
            XCTAssertFalse(ledger.reliable, mode)
        }
    }

    func testObserverDoesNotCancelDelayOrPreventOtherRecognizers() {
        let observer = ProbePhysicalTouches(), peer = UIPanGestureRecognizer()
        XCTAssertFalse(observer.cancelsTouchesInView)
        XCTAssertFalse(observer.delaysTouchesBegan); XCTAssertFalse(observer.delaysTouchesEnded)
        XCTAssertFalse(observer.canPrevent(peer)); XCTAssertFalse(observer.canBePrevented(by: peer))
        XCTAssertEqual(observer.state, .possible)
        observer.isEnabled = false; observer.isEnabled = true
        XCTAssertFalse(observer.ledger.reliable)
    }

    func testRepeatedInstallationKeepsOneObserverBeforeReadiness() throws {
        let (registry, window, handle) = try registered()
        let observer = ProbePhysicalOperationInput(registry: registry)
        XCTAssertEqual(registry.snapshot(logicalSceneID: "scene-A")?.readiness, .attached)
        XCTAssertNil(observer.install(window: window, handle: handle))
        let original = try XCTUnwrap(window.gestureRecognizers?.compactMap { $0 as? ProbePhysicalTouches }.first)
        for _ in 0..<3 { XCTAssertNil(observer.install(window: window, handle: handle)) }
        XCTAssertEqual(window.gestureRecognizers?.compactMap { $0 as? ProbePhysicalTouches }.count, 1)
        XCTAssertTrue(window.gestureRecognizers?.contains { $0 === original } == true)
        XCTAssertEqual(original.ledger.revision, 0)
        XCTAssertNotNil(registry.markReady(handle))
    }

    func testReplacementAndDetachedObserverCannotBeReinstalled() throws {
        for mode in ["root", "window", "disconnect", "detached", "disabled"] {
            let (registry, window, handle) = try registered()
            let observer = ProbePhysicalOperationInput(registry: registry)
            XCTAssertNil(observer.install(window: window, handle: handle))
            let touch = try XCTUnwrap(window.gestureRecognizers?.compactMap { $0 as? ProbePhysicalTouches }.first)
            var target = window
            switch mode {
            case "root": window.rootViewController = UIViewController()
            case "window":
                target = UIWindow(); target.rootViewController = UIViewController()
                _ = registry.register(logicalSceneID: handle.logicalSceneID, nativeSceneID: handle.nativeSceneID,
                                      window: target, currentRoute: ["home"])
            case "disconnect": _ = registry.disconnect(handle)
            case "detached": window.removeGestureRecognizer(touch)
            default: touch.isEnabled = false
            }
            XCTAssertNotNil(observer.install(window: target, handle: handle), mode)
            XCTAssertNotNil(observer.install(window: window, handle: handle), mode)
        }
    }

    func testIdleAllowsRecordedAuxiliaryWindowsWithoutCountingThemAsOwners() throws {
        let value = try edited { object in
            var inventory = object["inventory"] as! [[String: Any]]
            var windows = inventory[0]["windows"] as! [[String: Any]]
            var auxiliary = windows[0]
            auxiliary["identity"] = "framework-window"; auxiliary["rootIdentity"] = "framework-root"
            auxiliary.removeValue(forKey: "fixtureOwner"); auxiliary["key"] = false
            windows.append(auxiliary); inventory[0]["windows"] = windows; object["inventory"] = inventory
        }
        XCTAssertEqual(value.inventory[0].windows.count, 2)
        XCTAssertNil(value.idleFailure())
    }

    func testHeldMissingChangedOrUnreliableInputRejectsIdle() throws {
        XCTAssertNil(snapshot().idleFailure())
        for (key, value) in [("touches", 1 as Any), ("attached", false), ("enabled", false), ("reliable", false),
                              ("mounted", false), ("transitioning", true), ("resizing", true), ("generation", 1),
                              ("windowIdentity", "other"), ("rootIdentity", "other"), ("observerIdentity", "observer-scene-B")] {
            XCTAssertNotNil(try input(key, value).idleFailure(), key)
        }
        XCTAssertNotNil(try edited { $0["input"] = [] }.idleFailure())
        XCTAssertNotNil(try edited { $0["inventory"] = [] }.idleFailure())
        XCTAssertNotNil(try edited { $0["connectedSceneIDs"] = [] }.idleFailure())
        XCTAssertNotNil(try edited { $0["failure"] = "lost observer" }.idleFailure())
        XCTAssertNotNil(try edited { $0["applicationActive"] = false }.idleFailure())
    }

    func testCaptureBindsExactRequestAndOneUseResponse() throws {
        let exchange = try exchange(), raw = try request()
        let bytes = try exchange.capture(request: raw, observe: snapshot)
        let value = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: bytes)
        XCTAssertEqual(value.request, try JSONDecoder().decode(ProbePhysicalInputRequest.self, from: raw))
        XCTAssertEqual(value.requestSHA256, ProbePhysicalInputExchange.sha(raw))
        XCTAssertNotNil(UUID(uuidString: value.captureID)); XCTAssertNil(value.idleFailure)
        XCTAssertEqual(value.before.input, value.after.input)
        XCTAssertNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(bytes), live: snapshot()))
        XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(bytes), live: snapshot()))
        XCTAssertThrowsError(try exchange.capture(request: request(), observe: snapshot))
    }

    func testForeignMalformedAndUnknownRequestFieldsNeverCapture() throws {
        for field in ["runID", "processID", "profile", "phase", "nonce", "extra", "missing", "profileExtra"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: request()) as? [String: Any])
            switch field {
            case "processID": object[field] = 124
            case "profile", "profileExtra":
                var profile = object["profile"] as! [String: Any]
                profile[field == "profile" ? "buildConfiguration" : "extra"] = "Release"; object["profile"] = profile
            case "missing": object.removeValue(forKey: "nonce")
            default: object[field] = "foreign"
            }
            var observations = 0
            XCTAssertThrowsError(try exchange().capture(request: JSONSerialization.data(withJSONObject: object)) {
                observations += 1; return self.snapshot()
            }, field)
            XCTAssertEqual(observations, 0)
        }
        for raw in [Data("null".utf8), Data("{".utf8), Data(repeating: 0, count: 16_385)] {
            XCTAssertThrowsError(try exchange().capture(request: raw, observe: snapshot))
        }
    }

    func testDuplicateCaptureNonceAndPendingSetupAreRejected() throws {
        let exchange = try exchange(), raw = try request()
        let captured = try exchange.capture(request: raw, observe: snapshot)
        XCTAssertThrowsError(try exchange.capture(request: raw, observe: snapshot))
        XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(captured), live: snapshot()))
        XCTAssertThrowsError(try exchange.capture(request: request(), observe: snapshot))
    }

    func testContactChangeDuringCaptureIsRetainedAndCannotAdmit() throws {
        let exchange = try exchange(), changed = try input("revision", 11)
        var reads = 0
        let raw = try exchange.capture(request: request()) { reads += 1; return reads == 1 ? self.snapshot() : changed }
        let value = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: raw)
        XCTAssertEqual(value.before.input[0].revision, 10); XCTAssertEqual(value.after.input[0].revision, 11)
        XCTAssertNotNil(value.idleFailure)
        XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(raw), live: changed))
    }

    func testInterveningTouchOwnerChangeAndBadDigestConsumeSetupPermanently() throws {
        for mode in ["revision", "touches", "rootIdentity", "digest"] {
            let exchange = try exchange()
            let raw = try exchange.capture(request: request(), observe: snapshot)
            let changed = mode == "digest" ? snapshot() : try input(mode, mode == "rootIdentity" ? "foreign" : 11)
            let digest = mode == "digest" ? "wrong" : ProbePhysicalInputExchange.sha(raw)
            XCTAssertNotNil(exchange.consumeSetup(responseSHA256: digest, live: changed), mode)
            XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(raw), live: snapshot()), mode)
        }
    }

    func testChangedCompleteWindowInventoryRejectsCaptureAndConsumption() throws {
        for mode in ["addedWindow", "removedWindow", "addedScene", "removedScene", "keyWindow", "geometry"] {
            let original = try edited { object in
                var inventory = object["inventory"] as! [[String: Any]]
                var windows = inventory[0]["windows"] as! [[String: Any]]
                var auxiliary = windows[0]
                auxiliary["identity"] = "auxiliary"; auxiliary["rootIdentity"] = "auxiliary-root"
                auxiliary["key"] = false; auxiliary.removeValue(forKey: "fixtureOwner")
                windows.append(auxiliary); inventory[0]["windows"] = windows
                var foreign = inventory[0]
                foreign["nativeSceneID"] = "foreign"; foreign["windows"] = []; foreign.removeValue(forKey: "keyWindowIdentity")
                inventory.append(foreign); object["inventory"] = inventory
                object["connectedSceneIDs"] = ["native-scene-A", "native-scene-B", "foreign"]
            }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            var inventory = object["inventory"] as! [[String: Any]]
            var windows = inventory[0]["windows"] as! [[String: Any]]
            switch mode {
            case "addedWindow":
                var another = windows[1]; another["identity"] = "another"; windows.append(another)
            case "removedWindow": windows.removeLast()
            case "addedScene":
                var other = inventory[2]; other["nativeSceneID"] = "another"; inventory.append(other)
                object["connectedSceneIDs"] = ["native-scene-A", "native-scene-B", "foreign", "another"]
            case "removedScene":
                inventory.removeLast(); object["connectedSceneIDs"] = ["native-scene-A", "native-scene-B"]
            case "keyWindow":
                windows[0]["key"] = false; windows[1]["key"] = true; inventory[0]["keyWindowIdentity"] = "auxiliary"
            default: windows[1]["geometry"] = ["x": 1, "y": 0, "width": 400, "height": 800]
            }
            inventory[0]["windows"] = windows; object["inventory"] = inventory
            let changed = try JSONDecoder().decode(ProbePhysicalInputSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(original.idleFailure(), mode); XCTAssertNil(changed.idleFailure(), mode)
            let exchange = try exchange()
            let bytes = try exchange.capture(request: request()) { original }
            XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(bytes), live: changed), mode)
            let duringCapture = try self.exchange()
            var reads = 0
            let changedBytes = try duringCapture.capture(request: request()) { reads += 1; return reads == 1 ? original : changed }
            XCTAssertNotNil(try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: changedBytes).idleFailure, mode)
        }
    }

    func testMalformedRequestCannotLeavePriorSetupAdmissible() throws {
        let exchange = try exchange()
        let captured = try exchange.capture(request: request(), observe: snapshot)
        XCTAssertThrowsError(try exchange.capture(request: Data("{}".utf8), observe: snapshot))
        XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(captured), live: snapshot()))
        let cleanup = try exchange.capture(request: request(phase: "cleanup"), observe: snapshot)
        XCTAssertNil(try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: cleanup).idleFailure)
    }

    func testCleanupSnapshotCannotAuthorizeSetupOrHideHeldInput() throws {
        let exchange = try exchange()
        let setup = try exchange.capture(request: request(), observe: snapshot)
        let busy = try input("touches", 1)
        let raw = try exchange.capture(request: request(phase: "cleanup")) { busy }
        let value = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: raw)
        XCTAssertEqual(value.request.phase, "cleanup"); XCTAssertNotNil(value.idleFailure)
        XCTAssertNotNil(exchange.consumeSetup(responseSHA256: ProbePhysicalInputExchange.sha(setup), live: snapshot()))
        XCTAssertThrowsError(try exchange.capture(request: request(), observe: snapshot))
    }
}


@MainActor
final class ProbePhysicalOperationChannelTests: XCTestCase {
    private var observations = 0

    private func profile() throws -> ProbePhysicalOperationProfile {
        let scenario = try XCTUnwrap(ProbeScenarioCatalog.all.first { $0.identifier == ProbePhysicalOperationProfile.scenarioID })
        return try XCTUnwrap(ProbePhysicalOperationProfile.make(scenario: scenario,
                              sourceRevision: String(repeating: "a", count: 40), buildConfiguration: "Debug"))
    }

    private func code() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["runID": "channel-test", "processID": 123,
            "sourceRevision": String(repeating: "a", count: 40), "boundary": "before-sdk-initialization",
            "binaries": ["fixture": String(repeating: "b", count: 64)]], options: [.sortedKeys])
    }

    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func channel(_ directory: URL? = nil, publish: ((Data, URL) throws -> Void)? = nil,
                         mode: ProbePhysicalOperationChannel.Mode = .historical) throws -> ProbePhysicalOperationChannel {
        try .init(runID: "channel-test", processID: 123, profile: profile(), installedCode: code(),
                  directory: directory ?? folder(), observe: { [self] in
            observations += 1
            // Deliberately incomplete topology: transport must retain its idle
            // failure without promoting it to SDK or teardown permission.
            return .init(scenes: [], input: [], connectedSceneIDs: [], applicationActive: true, inventory: [], failure: nil)
        }, publish: publish, mode: mode)
    }

    private func request(_ channel: ProbePhysicalOperationChannel, phase: String = "setup", command: String = UUID().uuidString) throws -> Data {
        let input = ProbePhysicalInputRequest(runID: channel.identity.runID, processID: channel.identity.processID,
                                             profile: channel.identity.profile, phase: phase, nonce: UUID().uuidString,
                                             setupProfile: channel.identity.setupProfile)
        return try ProbePhysicalOperationChannel.encode(ProbePhysicalOperationMessage(schemaVersion: channel.identity.schemaVersion,
            runID: channel.identity.runID, processID: channel.identity.processID, challengeID: channel.identity.challengeID,
            commandID: command, inputRequest: ProbePhysicalOperationChannel.encode(input)))
    }

    private func publish(_ raw: Data, _ channel: ProbePhysicalOperationChannel) throws {
        let digest = ProbePhysicalInputExchange.sha(raw)
        try raw.write(to: channel.url("request-" + digest + ".json"), options: .atomic)
        try Data(digest.utf8).write(to: channel.url("request"), options: .atomic)
    }

    private func setupProfile() throws -> ProbePhysicalOperationSetupProfile {
        let scenario = try XCTUnwrap(ProbeScenarioCatalog.scenario(identifier: ProbePhysicalOperationSetupProfile.scenarioID))
        return try XCTUnwrap(ProbePhysicalOperationSetupProfile.make(scenario: scenario))
    }

    func testPhysicalModeHasSeparateSchemaAndCannotArmExecution() throws {
        let setup = try setupProfile(), value = try channel(mode: .physicalSetup(setup))
        XCTAssertEqual(value.identity.schemaVersion, 2)
        XCTAssertEqual(value.identity.setupProfile, setup); XCTAssertFalse(value.identity.executionArmed)
        try publish(request(value), value)
        let result = try XCTUnwrap(value.poll())
        XCTAssertNil(result.rejection)
        let capture = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: XCTUnwrap(result.capture))
        XCTAssertEqual(capture.request.setupProfile, setup)
        XCTAssertNotNil(capture.idleFailure); XCTAssertFalse(result.identity.executionArmed)
    }

    func testHistoricalRequestAndChallengeBytesKeepTheirExactShape() throws {
        let value = try channel()
        let encoded = try ProbePhysicalOperationChannel.encode(value.identity)
        let profileText = try XCTUnwrap(String(data: ProbePhysicalOperationChannel.encode(value.identity.profile), encoding: .utf8))
        let expected = "{\"challengeID\":\"" + value.identity.challengeID + "\",\"executionArmed\":false,\"installedCodeSHA256\":\""
            + value.identity.installedCodeSHA256 + "\",\"processID\":123,\"profile\":" + profileText
            + ",\"runID\":\"channel-test\",\"schemaVersion\":1}"
        XCTAssertEqual(encoded, Data(expected.utf8))
        let request = ProbePhysicalInputRequest(runID: "channel-test", processID: 123, profile: value.identity.profile,
                                                phase: "setup", nonce: "00000000-0000-0000-0000-000000000001")
        let requestExpected = "{\"nonce\":\"00000000-0000-0000-0000-000000000001\",\"phase\":\"setup\",\"processID\":123,\"profile\":"
            + profileText + ",\"runID\":\"channel-test\"}"
        XCTAssertEqual(try ProbePhysicalOperationChannel.encode(request), Data(requestExpected.utf8))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: ProbePhysicalOperationChannel.encode(value.identity.profile)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["buildConfiguration", "sourceRevision", "scenarioSHA256", "inference"])
    }

    func testCrossModeAndAlteredSetupRequestsRejectBeforeObservation() throws {
        for physical in [false, true] {
            for field in ["schemaVersion", "setupProfile", "digest", "index", "unknown", "null"] {
                let setup = try setupProfile()
                let value = try channel(mode: physical ? .physicalSetup(setup) : .historical)
                let raw = try request(value)
                var message = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
                var inner = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(base64Encoded: message["inputRequest"] as! String)!) as? [String: Any])
                if field == "schemaVersion" { message[field] = physical ? 1 : 2 }
                else if field == "null" { inner["setupProfile"] = NSNull() }
                else if physical && field == "setupProfile" { inner.removeValue(forKey: "setupProfile") }
                else {
                    var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
                    if field == "digest" { changed["fullScenarioSHA256"] = String(repeating: "f", count: 64) }
                    if field == "index" { changed["setupBoundaryIndex"] = 6 }
                    if field == "unknown" { changed["unreviewed"] = true }
                    inner["setupProfile"] = changed
                }
                message["inputRequest"] = try JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys, .withoutEscapingSlashes]).base64EncodedString()
                let bytes = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
                let count = observations
                try publish(bytes, value)
                XCTAssertNotNil(try XCTUnwrap(value.poll()).rejection, field)
                XCTAssertEqual(observations, count, field)
            }
        }
    }

    func testChangedSetupProfileCannotCreateNativeChallenge() throws {
        let setup = try setupProfile()
        for field in ["variant", "scenario", "fullScenarioSHA256", "setupPrefixSHA256", "setupBoundaryIndex", "firstOperationIndex", "lastOperationIndex", "ownerBindingVersion"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
            if object[field] is String { object[field] = "foreign" } else { object[field] = 99 }
            let changed = try JSONDecoder().decode(ProbePhysicalOperationSetupProfile.self, from: JSONSerialization.data(withJSONObject: object))
            let directory = try folder()
            XCTAssertThrowsError(try channel(directory, mode: .physicalSetup(changed)), field)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty, field)
        }
    }

    func testChallengeBindsInstalledBytesAndRejectsRestoredDirectory() throws {
        let directory = try folder(), value = try channel(directory)
        let saved = try Data(contentsOf: value.url("challenge.json"))
        XCTAssertEqual(try JSONDecoder().decode(ProbePhysicalOperationChannelIdentity.self, from: saved), value.identity)
        XCTAssertEqual(value.identity.installedCodeSHA256, try ProbePhysicalInputExchange.sha(code()))
        XCTAssertFalse(value.identity.executionArmed)
        XCTAssertThrowsError(try channel(directory))
        XCTAssertEqual(try Data(contentsOf: value.url("challenge.json")), saved)
    }

    func testWrongInstalledRunProcessSourceOrBoundaryCreatesNoChallenge() throws {
        for (key, value) in [("runID", "other" as Any), ("processID", 124), ("sourceRevision", String(repeating: "c", count: 40)),
                             ("boundary", "after-sdk-initialization"), ("binaries", [:] as [String: String])] {
            let directory = try folder()
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: code()) as? [String: Any]); fields[key] = value
            XCTAssertThrowsError(try ProbePhysicalOperationChannel(runID: "channel-test", processID: 123, profile: profile(),
                installedCode: JSONSerialization.data(withJSONObject: fields), directory: directory, observe: { fatalError("must not observe") }))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        }
    }

    func testTornMissingAndMismatchedPublicationNeverCaptures() throws {
        let value = try channel(), raw = try request(value), hash = ProbePhysicalInputExchange.sha(raw)
        XCTAssertNil(try value.poll())
        for fragment in ["", String(hash.prefix(16)), String(repeating: "g", count: 64), hash] {
            try Data(fragment.utf8).write(to: value.url("request"), options: .atomic)
            XCTAssertNil(try value.poll())
        }
        try Data(raw.prefix(20)).write(to: value.url("request-" + hash + ".json"))
        XCTAssertNil(try value.poll()); XCTAssertEqual(observations, 0)
        try publish(raw, value)
        XCTAssertNotNil(try value.poll()?.capture); XCTAssertEqual(observations, 2)
    }

    func testOneUseResponseRetainsActualNonidleCapture() throws {
        let value = try channel(), raw = try request(value)
        try publish(raw, value)
        let reply = try XCTUnwrap(value.poll())
        let capture = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: XCTUnwrap(reply.capture))
        XCTAssertNotNil(capture.idleFailure); XCTAssertEqual(capture.before, capture.after)
        XCTAssertEqual(reply.requestSHA256, ProbePhysicalInputExchange.sha(raw))
        XCTAssertNil(reply.rejection); XCTAssertFalse(reply.identity.executionArmed)
        let output = value.url("response-" + reply.requestSHA256 + ".json")
        let saved = try Data(contentsOf: output)
        for _ in 0..<3 { XCTAssertNil(try value.poll()) }
        XCTAssertEqual(observations, 2); XCTAssertEqual(try Data(contentsOf: output), saved)
    }

    func testForeignUnknownDuplicateAndNoncanonicalFieldsRejectBeforeCapture() throws {
        for mode in ["runID", "processID", "challengeID", "extra", "duplicate", "newline"] {
            let value = try channel(), raw = try request(value)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            if mode == "runID" { object[mode] = "old" }
            if mode == "processID" { object[mode] = 124 }
            if mode == "challengeID" { object[mode] = UUID().uuidString }
            if mode == "extra" { object[mode] = true }
            var changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            if mode == "duplicate" { changed = Data("{\"schemaVersion\":1,".utf8) + changed.dropFirst() }
            if mode == "newline" { changed.append(10) }
            let before = observations
            try publish(changed, value)
            let reply = try XCTUnwrap(value.poll())
            XCTAssertNotNil(reply.rejection, mode); XCTAssertNil(reply.capture, mode)
            XCTAssertEqual(observations, before, mode); XCTAssertNotNil(value.failure, mode)
        }
    }

    func testMalformedInnerRequestsRejectBeforeObservation() throws {
        for mode in ["duplicate", "unknown", "whitespace", "profile"] {
            let value = try channel(), original = try request(value)
            let message = try JSONDecoder().decode(ProbePhysicalOperationMessage.self, from: original)
            var inner = message.inputRequest
            switch mode {
            case "duplicate": inner = Data("{\"phase\":\"setup\",".utf8) + inner.dropFirst()
            case "unknown": inner = Data("{\"extra\":true,".utf8) + inner.dropFirst()
            case "profile":
                let text = try XCTUnwrap(String(data: inner, encoding: .utf8))
                inner = Data(text.replacingOccurrences(of: "\"profile\":{", with: "\"profile\":{\"extra\":true,").utf8)
            default: inner.append(10)
            }
            let changed = ProbePhysicalOperationMessage(schemaVersion: message.schemaVersion, runID: message.runID,
                processID: message.processID, challengeID: message.challengeID, commandID: message.commandID, inputRequest: inner)
            try publish(ProbePhysicalOperationChannel.encode(changed), value)
            let before = observations
            XCTAssertNotNil(try value.poll()?.rejection, mode); XCTAssertEqual(observations, before, mode)
        }
    }

    func testReusedCommandAndReappearedPublicationCannotRecapture() throws {
        let value = try channel(), command = UUID().uuidString
        let first = try request(value, command: command)
        try publish(first, value); XCTAssertNotNil(try value.poll()?.capture)
        let next = try request(value, phase: "cleanup", command: command)
        try publish(next, value); XCTAssertNotNil(try value.poll()?.rejection)
        XCTAssertEqual(observations, 2)
        try publish(first, value); XCTAssertThrowsError(try value.poll())
        XCTAssertEqual(observations, 2)
    }

    func testReservedResponseStopsBeforeConsumingReadiness() throws {
        let value = try channel(), raw = try request(value)
        let output = value.url("response-" + ProbePhysicalInputExchange.sha(raw) + ".json")
        let old = Data("old response".utf8); try old.write(to: output)
        try publish(raw, value); XCTAssertThrowsError(try value.poll())
        XCTAssertEqual(observations, 0); XCTAssertEqual(try Data(contentsOf: output), old)
        XCTAssertNotNil(value.failure)
    }

    func testFailedResponsePersistenceLeavesSetupBlockedButCleanupAvailable() throws {
        var refuseResponse = true
        let value = try channel(publish: { bytes, url in
            if url.lastPathComponent.contains("response-"), refuseResponse { refuseResponse = false; throw CocoaError(.fileWriteUnknown) }
            guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
            try bytes.write(to: url, options: .atomic)
        })
        try publish(request(value), value); XCTAssertThrowsError(try value.poll()); XCTAssertNotNil(value.failure)
        try publish(request(value), value); XCTAssertNotNil(try value.poll()?.rejection)
        XCTAssertEqual(observations, 2)
        try publish(request(value, phase: "cleanup"), value)
        XCTAssertNotNil(try value.poll()?.capture); XCTAssertEqual(observations, 4)
        XCTAssertFalse(value.identity.executionArmed)
    }

    func testOversizedAndSymlinkedRequestsDoNotObserve() throws {
        for mode in ["oversized", "symlink"] {
            let value = try channel(), bytes = Data(repeating: 65, count: mode == "oversized" ? 65_537 : 1)
            let hash = ProbePhysicalInputExchange.sha(bytes), target = value.url("request-" + hash + ".json")
            if mode == "symlink" {
                let source = value.url("foreign"); try bytes.write(to: source)
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
            } else { try bytes.write(to: target) }
            try Data(hash.utf8).write(to: value.url("request"))
            let before = observations
            XCTAssertThrowsError(try value.poll()); XCTAssertEqual(observations, before)
        }
    }

    func testCanonicalEnvelopeMatchesHostEncodingIncludingBase64Slash() throws {
        let value = ProbePhysicalOperationMessage(schemaVersion: 1, runID: "run", processID: 123,
            challengeID: "00000000-0000-0000-0000-000000000001", commandID: "00000000-0000-0000-0000-000000000002", inputRequest: Data([255]))
        let expected = #"{"challengeID":"00000000-0000-0000-0000-000000000001","commandID":"00000000-0000-0000-0000-000000000002","inputRequest":"/w==","processID":123,"runID":"run","schemaVersion":1}"#
        XCTAssertEqual(try ProbePhysicalOperationChannel.encode(value), Data(expected.utf8))
    }
}

@MainActor
final class ProbePhysicalOperationOwnerTests: XCTestCase {
    private let runID = "owner-test"
    private let applicationID = "00000000-0000-0000-0000-000000000010"
    private let sessionID = "00000000-0000-0000-0000-000000000011"
    private func snapshot() -> ProbePhysicalInputSnapshot {
        let scenes: [ProbePhysicalSceneObservation] = ["scene-A", "scene-B"].enumerated().map { index, label in
            .init(logicalSceneID: label, nativeSceneID: "native-" + label, generation: 0, connected: true,
                  activationState: index == 0 ? "foreground-inactive" : "foreground-active", hidden: false, alpha: 1,
                  geometry: .init(x: Double(index) * 400, y: 0, width: 400, height: 800),
                  windowIdentity: "window-" + label, rootIdentity: "root-" + label)
        }
        let input = scenes.map { row in
            ProbePhysicalInputWindow(logicalSceneID: row.logicalSceneID, nativeSceneID: row.nativeSceneID, generation: 0,
                windowIdentity: row.windowIdentity!, rootIdentity: row.rootIdentity!, observerIdentity: "observer-" + row.logicalSceneID,
                attached: true, enabled: true, reliable: true, touches: 0, revision: 10, mounted: true, transitioning: false, resizing: false)
        }
        let inventory = scenes.map { row in
            ProbePhysicalSceneInventory(nativeSceneID: row.nativeSceneID, activationState: row.activationState,
                keyWindowIdentity: row.windowIdentity, geometry: row.geometry, screenGeometry: .init(x: 0, y: 0, width: 800, height: 800),
                windows: [.init(identity: row.windowIdentity!, rootIdentity: row.rootIdentity, fixtureOwner: row.logicalSceneID,
                                sceneMatches: true, key: true, hidden: false, alpha: 1, mounted: true, geometry: row.geometry)])
        }
        return .init(scenes: scenes, input: input, connectedSceneIDs: scenes.map(\.nativeSceneID),
                     applicationActive: true, inventory: inventory, failure: nil)
    }

    private func profile() throws -> ProbePhysicalOperationSetupProfile {
        try XCTUnwrap(ProbePhysicalOperationSetupProfile.make(scenario: XCTUnwrap(
            ProbeScenarioCatalog.scenario(identifier: ProbePhysicalOperationSetupProfile.scenarioID))))
    }
    private func contexts() -> [String: ProbePhysicalOperationRUMOwner] {
        Dictionary(uniqueKeysWithValues: ["scene-A", "scene-B"].enumerated().map { index, scene in
            (scene, .init(logicalSceneID: scene, nativeSceneID: "native-" + scene, applicationID: applicationID,
                         sessionID: sessionID, viewID: "00000000-0000-0000-0000-00000000002" + String(index),
                         viewName: "ProbeHomeView", viewURL: "ProbeHomeView"))
        })
    }
    private func views() -> [ProbeSignal] {
        ["scene-A", "scene-B"].enumerated().map { index, scene in
            let owner = contexts()[scene]!
            return ProbeSignal(kind: .rumViewSnapshot, evidenceSource: .rumMapper,
                sequence: UInt64(index + 1), runID: runID, scenarioID: ProbePhysicalOperationSetupProfile.scenarioID,
                semanticContext: .init(logicalSceneID: scene, nativeSceneID: owner.nativeSceneID, screen: "home"),
                rumContext: .init(sessionID: sessionID, viewID: owner.viewID, viewName: owner.viewName,
                                  viewURL: owner.viewURL, viewActive: true, viewDocumentVersion: 2))
        }
    }
    private func binding(signals: [ProbeSignal]? = nil, before: [String: ProbePhysicalOperationRUMOwner]? = nil,
                         after: [String: ProbePhysicalOperationRUMOwner]? = nil,
                         nativeAfter: ProbePhysicalInputSnapshot? = nil) throws -> ProbePhysicalOperationOwners? {
        ProbePhysicalOperationOwners.bind(runID: runID, processID: 123, profile: try profile(),
            setupCaptureSHA256: String(repeating: "a", count: 64), applicationID: applicationID,
            before: snapshot(), after: nativeAfter ?? snapshot(), directBefore: before ?? contexts(),
            directAfter: after ?? contexts(), signals: signals ?? views())
    }
    private func edit<T: Codable>(_ value: T, _ change: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func markers() -> [ProbeSignal] {
        ProbePhysicalOperationSetupProfile.steps.enumerated().flatMap { index, step -> [ProbeSignal] in
            guard step.kind == .emitSceneContextMarker, let scene = step.scene, let name = step.value else { return [] }
            let owner = contexts()[scene]!
            return [ProbeSignalKind.rumAction, .rumResource].enumerated().map { offset, kind in
                let id = UUID().uuidString.lowercased()
                return ProbeSignal(kind: kind, evidenceSource: .rumMapper, sequence: UInt64(100 + 2 * index + offset),
                    runID: runID, scenarioID: ProbePhysicalOperationSetupProfile.scenarioID,
                    sourceContext: .init(logicalSceneID: scene, nativeSceneID: owner.nativeSceneID, screen: "home", phase: name),
                    rumContext: .init(sessionID: sessionID, viewID: owner.viewID, viewName: owner.viewName, viewURL: owner.viewURL),
                    eventID: id, name: name,
                    action: kind == .rumAction ? .init(id: id, type: "custom", target: "probe-lifecycle-" + scene + ".home." + name,
                        loadingTimeNanoseconds: nil) : nil,
                    resource: kind == .rumResource ? .init(id: id, type: "other", statusCode: 200, durationNanoseconds: nil,
                        size: 1, method: nil, url: "https://multi-scene-probe.invalid/native/" + scene + "/home/" + name,
                        traceID: nil, spanID: nil, parentSpanID: nil) : nil)
            }
        }
    }
    private func calls() -> [ProbeSignal] {
        ProbePhysicalOperationSetupProfile.steps.enumerated().compactMap { index, step in
            guard [.startOperation, .succeedOperation, .failOperation].contains(step.kind),
                  let scene = step.scene, let instance = step.value else { return nil }
            return ProbeSignal(kind: .assertion, sequence: UInt64(10 + index), runID: runID,
                scenarioID: ProbePhysicalOperationSetupProfile.scenarioID,
                semanticContext: .init(logicalSceneID: scene, nativeSceneID: contexts()[scene]!.nativeSceneID, screen: "home"),
                stepKind: step.kind, operation: .init(vitalID: nil, name: "multi_scene_probe_navigation", key: runID + "-" + instance,
                    step: step.kind == .startOperation ? "start" : step.kind == .succeedOperation ? "succeed" : "fail",
                    failureReason: step.kind == .failOperation ? "error" : nil), result: .pass)
        }
    }

    func testVariantKeepsCallsAndUsesDistinctPostArrangementMarkers() throws {
        let scenario = try XCTUnwrap(ProbeScenarioCatalog.scenario(identifier: ProbePhysicalOperationSetupProfile.scenarioID))
        let original = try XCTUnwrap(ProbeScenarioCatalog.scenario(identifier: ProbePhysicalOperationProfile.scenarioID))
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExplicitOperationViewTargetSPI(scenario))
        XCTAssertEqual(Array(scenario.steps[6...21]), Array(original.steps[6...21]))
        XCTAssertEqual(scenario.steps[2], .init(.openWindow, scene: "scene-A", value: "scene-B"))
        XCTAssertEqual(scenario.steps[4].value, "operation-arranged-home-a")
        XCTAssertEqual(scenario.steps[5].value, "operation-arranged-home-b")
        XCTAssertEqual(try profile().setupBoundaryIndex, 4)
        XCTAssertNotEqual(try profile().fullScenarioSHA256, try profile().setupPrefixSHA256)
        XCTAssertNil(ProbePhysicalOperationSetupProfile.make(scenario: original))
        XCTAssertNil(ProbePhysicalOperationProfile.make(scenario: scenario, sourceRevision: String(repeating: "a", count: 40), buildConfiguration: "Debug"))
        for field in ["identifier", "steps", "completionConditions", "expectedSemanticTimeline", "runtimeOptions"] {
            let changed: ProbeScenario = try edit(scenario) { object in
                if field == "identifier" { object[field] = original.identifier }
                else if field == "runtimeOptions" {
                    var options = object[field] as! [String: Any]
                    options["automaticallyClosesSceneB"] = true
                    object[field] = options
                }
                else if field == "expectedSemanticTimeline" { object[field] = [["kind": "view-started", "occurrence": 1]] }
                else { object[field] = [] }
            }
            XCTAssertNil(ProbePhysicalOperationSetupProfile.make(scenario: changed), field)
        }
    }

    func testFreshPostArrangementOccurrenceBindsWithoutRelabelingOldHome() throws {
        let old: ProbeSignal = try edit(views()[0]) { object in
            object["sequence"] = 3
            var rum = object["rumContext"] as! [String: Any]
            rum["viewID"] = "00000000-0000-0000-0000-000000000030"; rum["viewActive"] = false
            object["rumContext"] = rum
        }
        let signals = [old] + views()
        let value = try XCTUnwrap(binding(signals: signals))
        XCTAssertEqual(value.contexts["scene-A"]?.viewID, contexts()["scene-A"]?.viewID)
        XCTAssertNotEqual(value.contexts["scene-A"]?.viewID, old.rumContext?.viewID)
        XCTAssertEqual(signals.first, old)
        var stale = contexts()
        stale["scene-A"] = try edit(stale["scene-A"]!) { $0["viewID"] = old.rumContext!.viewID! }
        XCTAssertNil(try binding(signals: signals, before: stale, after: stale))
    }

    func testOwnerBindingRejectsMissingAliasedAndChangedDirectContexts() throws {
        XCTAssertNil(try binding(before: [:], after: [:]))
        for field in ["viewID", "sessionID", "applicationID", "logicalSceneID", "nativeSceneID", "viewName", "viewURL"] {
            var changed = contexts()
            changed["scene-A"] = try edit(changed["scene-A"]!) { $0[field] = "foreign" }
            XCTAssertNil(try binding(before: changed, after: changed), field)
            XCTAssertNil(try binding(after: changed), field)
        }
        var alias = contexts()
        alias["scene-A"] = try edit(alias["scene-A"]!) { $0["viewID"] = contexts()["scene-B"]!.viewID }
        XCTAssertNil(try binding(before: alias, after: alias))
    }

    func testSessionBoundaryWhileWaitingForMapperCannotBind() throws {
        var newer = contexts()
        for scene in ["scene-A", "scene-B"] {
            newer[scene] = try edit(newer[scene]!) { $0["sessionID"] = "00000000-0000-0000-0000-000000000099" }
        }
        let changed = try views().map { row in try edit(row) { object in
            var rum = object["rumContext"] as! [String: Any]; rum["sessionID"] = "00000000-0000-0000-0000-000000000099"; object["rumContext"] = rum
        } }
        XCTAssertNil(try binding(signals: changed, after: newer))
        XCTAssertNotNil(try binding(signals: changed, before: newer, after: newer))
    }

    func testMapperNeedsExactSemanticOwnerAndCurrentDocumentVersion() throws {
        XCTAssertNil(try binding(signals: []))
        for field in ["runID", "scenarioID", "evidenceSource", "viewName", "nativeSceneID", "viewActive", "viewDocumentVersion"] {
            var rows = views()
            rows[0] = try edit(rows[0]) { object in
                if ["runID", "scenarioID"].contains(field) { object[field] = "old" }
                else if field == "evidenceSource" { object[field] = "internal-hook" }
                else if field == "nativeSceneID" {
                    var context = object["semanticContext"] as! [String: Any]; context[field] = "wrong"; object["semanticContext"] = context
                } else {
                    var context = object["rumContext"] as! [String: Any]
                    if field == "viewName" { context[field] = "WrongView" }
                    if field == "viewActive" { context[field] = false }
                    if field == "viewDocumentVersion" { context[field] = 0 }
                    object["rumContext"] = context
                }
            }
            XCTAssertNil(try binding(signals: rows), field)
        }
        let inactive: ProbeSignal = try edit(views()[0]) { object in
            object["sequence"] = 3; var rum = object["rumContext"] as! [String: Any]
            rum["viewDocumentVersion"] = 3; rum["viewActive"] = false; object["rumContext"] = rum
        }
        XCTAssertNil(try binding(signals: [inactive] + views()))
        XCTAssertNil(try binding(signals: views() + [views()[0]]))
    }

    func testNativeOrInputChangeAcrossWaitRejectsBinding() throws {
        let changed: ProbePhysicalInputSnapshot = try edit(snapshot()) { object in
            var input = object["input"] as! [[String: Any]]; input[0]["revision"] = 11; object["input"] = input
        }
        XCTAssertNil(try binding(nativeAfter: changed))
    }

    func testMarkerJoinUsesBoundOwnerRatherThanMapperOrder() throws {
        let value = try XCTUnwrap(binding())
        let rows = markers() + calls() + views()
        XCTAssertNil(value.workFailure(signals: rows.reversed()))
        let lateViews = try views().map { row in try edit(row) { $0["sequence"] = row.sequence + 1_000 } }
        XCTAssertNil(value.workFailure(signals: markers() + calls() + lateViews))
        let before = markers().filter { $0.name == "operation-arranged-home-a" }
        XCTAssertNil(value.markerFailure("operation-arranged-home-a", scene: "scene-A", kind: .rumAction, signals: before))
    }

    func testMissingDuplicateOrWrongMarkerOwnerRejects() throws {
        let value = try XCTUnwrap(binding()), original = markers()
        XCTAssertNotNil(value.workFailure(signals: Array(original.dropLast()) + calls()))
        XCTAssertNotNil(value.workFailure(signals: original + calls() + [original[0]]))
        for field in ["viewID", "viewName", "sessionID", "sourceScene", "eventID"] {
            var rows = original
            rows[0] = try edit(rows[0]) { object in
                if field == "eventID" { object.removeValue(forKey: field) }
                else if field == "sourceScene" {
                    var context = object["sourceContext"] as! [String: Any]; context["logicalSceneID"] = "scene-B"; object["sourceContext"] = context
                } else {
                    var rum = object["rumContext"] as! [String: Any]; rum[field] = contexts()["scene-B"]!.viewID; object["rumContext"] = rum
                }
            }
            XCTAssertNotNil(value.workFailure(signals: rows + calls()), field)
        }
    }

    func testCallInventoryRejectsMissingDuplicateReorderedAndWrongNativeScene() throws {
        let value = try XCTUnwrap(binding()), original = calls()
        XCTAssertNotNil(value.workFailure(signals: markers() + original.dropLast()))
        XCTAssertNotNil(value.workFailure(signals: markers() + original + [original[0]]))
        var reordered = original
        reordered[0] = try edit(original[0]) { $0["sequence"] = 99 }
        XCTAssertNotNil(value.workFailure(signals: markers() + reordered))
        var wrong = original
        wrong[0] = try edit(original[0]) { object in
            var semantic = object["semanticContext"] as! [String: Any]; semantic["nativeSceneID"] = "wrong"; object["semanticContext"] = semantic
        }
        XCTAssertNotNil(value.workFailure(signals: markers() + wrong))
    }

    func testWholeIntervalIncludesSetupMarkersBeforeFirstOperation() throws {
        let owners = try XCTUnwrap(binding())
        var progress = ProbePhysicalOperationOwners.Progress(owners: owners)
        for index in ProbePhysicalOperationSetupProfile.guardInterval {
            for after in [false, true] {
                XCTAssertNil(progress.check(index: index, step: ProbePhysicalOperationSetupProfile.steps[index], after: after,
                    input: snapshot(), contexts: contexts(), signals: markers()), "index \(index) after \(after)")
            }
        }
        XCTAssertTrue(progress.complete)
        var skipped = ProbePhysicalOperationOwners.Progress(owners: owners)
        XCTAssertNotNil(skipped.check(index: 6, step: ProbePhysicalOperationSetupProfile.steps[6], after: false,
            input: snapshot(), contexts: contexts(), signals: markers()))
        XCTAssertNotNil(skipped.check(index: 4, step: ProbePhysicalOperationSetupProfile.steps[4], after: false,
            input: snapshot(), contexts: contexts(), signals: markers()))
        var missing = ProbePhysicalOperationOwners.Progress(owners: owners)
        XCTAssertNil(missing.check(index: 4, step: ProbePhysicalOperationSetupProfile.steps[4], after: false,
            input: snapshot(), contexts: contexts(), signals: []))
        XCTAssertNotNil(missing.check(index: 4, step: ProbePhysicalOperationSetupProfile.steps[4], after: true,
            input: snapshot(), contexts: contexts(), signals: []))
    }

    func testTopologyAndRUMDriftFailPermanentlyDuringCriticalInterval() throws {
        let owners = try XCTUnwrap(binding())
        for field in ["revision", "touches", "transitioning", "resizing", "rootIdentity"] {
            let changed: ProbePhysicalInputSnapshot = try edit(snapshot()) { object in
                var input = object["input"] as! [[String: Any]]
                if field == "rootIdentity" { input[0][field] = "replaced" }
                else if ["transitioning", "resizing"].contains(field) { input[0][field] = true }
                else { input[0][field] = 11 }
                object["input"] = input
            }
            var progress = ProbePhysicalOperationOwners.Progress(owners: owners)
            XCTAssertNotNil(progress.observe(input: changed, contexts: contexts()), field)
            XCTAssertNotNil(progress.observe(input: snapshot(), contexts: contexts()), field)
        }
        var changed = contexts()
        changed["scene-A"] = try edit(changed["scene-A"]!) { $0["viewID"] = "00000000-0000-0000-0000-000000000098" }
        var progress = ProbePhysicalOperationOwners.Progress(owners: owners)
        XCTAssertNotNil(progress.observe(input: snapshot(), contexts: changed))
        XCTAssertNotNil(progress.observe(input: snapshot(), contexts: contexts()))
    }

    private func sdkValues() -> [String: ProbePhysicalOperationSDKValue] {
        Dictionary(uniqueKeysWithValues: contexts().values.map {
            ($0.nativeSceneID, .init(applicationID: $0.applicationID, sessionID: $0.sessionID,
                viewID: $0.viewID, viewName: $0.viewName, viewURL: $0.viewURL))
        })
    }

    private func sample(values: [String: ProbePhysicalOperationSDKValue]? = nil) -> ProbePhysicalOperationContextSample {
        let rows = values ?? sdkValues()
        return ProbePhysicalOperationContextSampler(observeInput: snapshot, readContext: { nativeID, _ in rows[nativeID] }).sample()
    }

    func testSamplerUsesExactNativeTargetsAndOneDate() throws {
        let expectedDate = Date(timeIntervalSince1970: 123), values = sdkValues(), input = snapshot()
        var targets: [String] = [], dates: [Date] = []
        var inputReads = 0, clockReads = 0
        let sampler = ProbePhysicalOperationContextSampler(observeInput: {
            inputReads += 1; return input
        }, readContext: { nativeID, date in
            targets.append(nativeID); dates.append(date); return values[nativeID]
        }, now: { clockReads += 1; return expectedDate })
        let capture = sampler.sample()
        XCTAssertNil(capture.failure)
        XCTAssertEqual(targets, ["native-scene-A", "native-scene-B"])
        XCTAssertEqual(dates, [expectedDate, expectedDate])
        XCTAssertEqual(clockReads, 1); XCTAssertEqual(inputReads, 2)
        XCTAssertEqual(capture.sampledAt, expectedDate)
        XCTAssertEqual(capture.before, input); XCTAssertEqual(capture.after, input)
        XCTAssertEqual(capture.ownerProjection, contexts())
        XCTAssertEqual(try JSONDecoder().decode(ProbePhysicalOperationContextSample.self,
            from: JSONEncoder().encode(capture)), capture)
    }

    func testSamplerRetainsUnavailableExpiredAndIncompleteContexts() throws {
        var missing = sdkValues(); missing.removeValue(forKey: "native-scene-A")
        let unavailable = sample(values: missing)
        XCTAssertNotNil(unavailable.failure); XCTAssertNil(unavailable.ownerProjection)
        XCTAssertEqual(unavailable.reads.count, 2)
        XCTAssertNil(unavailable.reads[0].value)
        XCTAssertEqual(unavailable.reads[1].value, missing["native-scene-B"])
        // The session-aware SDK reader returns nil for an expired or absent scene.
        for field in ["applicationID", "sessionID", "viewID", "viewName", "viewURL"] {
            for replacement in ["", "invalid"] {
                if ["viewName", "viewURL"].contains(field) && replacement == "invalid" { continue }
                var changed = sdkValues()
                changed["native-scene-A"] = try edit(changed["native-scene-A"]!) { $0[field] = replacement }
                let capture = sample(values: changed)
                XCTAssertNotNil(capture.failure, field); XCTAssertNil(capture.ownerProjection, field)
                XCTAssertEqual(capture.reads[0].value, changed["native-scene-A"])
            }
        }
        for field in ["viewID", "viewName", "viewURL"] {
            var changed = sdkValues()
            changed["native-scene-A"] = try edit(changed["native-scene-A"]!) { $0.removeValue(forKey: field) }
            XCTAssertNil(sample(values: changed).ownerProjection, field)
        }
    }

    func testSamplerRejectsDifferentApplicationsSessionsAndAliasedViews() throws {
        for field in ["applicationID", "sessionID", "viewID"] {
            var changed = sdkValues()
            changed["native-scene-B"] = try edit(changed["native-scene-B"]!) {
                $0[field] = field == "viewID" ? changed["native-scene-A"]!.viewID! : "00000000-0000-0000-0000-000000000099"
            }
            let capture = sample(values: changed)
            XCTAssertNotNil(capture.failure); XCTAssertNil(capture.ownerProjection)
            XCTAssertEqual(capture.reads[1].value, changed["native-scene-B"])
        }
    }

    func testSamplerRetainsInputChangeDuringSDKReads() throws {
        let original = snapshot(), values = sdkValues()
        let changed: ProbePhysicalInputSnapshot = try edit(original) { object in
            var rows = object["input"] as! [[String: Any]]; rows[0]["revision"] = 11; object["input"] = rows
        }
        var live = original
        let capture = ProbePhysicalOperationContextSampler(observeInput: { live }, readContext: { nativeID, _ in
            live = changed; return values[nativeID]
        }).sample()
        XCTAssertEqual(capture.before, original); XCTAssertEqual(capture.after, changed)
        XCTAssertEqual(capture.reads.count, 2)
        XCTAssertNotNil(capture.failure); XCTAssertNil(capture.ownerProjection)
    }

    func testSamplerDoesNotReadSDKWhenInputIsInvalid() throws {
        let held: ProbePhysicalInputSnapshot = try edit(snapshot()) { object in
            var rows = object["input"] as! [[String: Any]]; rows[0]["touches"] = 1; object["input"] = rows
        }
        var reads = 0
        let capture = ProbePhysicalOperationContextSampler(observeInput: { held }, readContext: { _, _ in
            reads += 1; return nil
        }).sample()
        XCTAssertEqual(reads, 0); XCTAssertEqual(capture.reads, [])
        XCTAssertEqual(capture.before, held); XCTAssertEqual(capture.after, held)
        XCTAssertNotNil(capture.failure); XCTAssertNil(capture.ownerProjection)
    }

    func testSamplerProjectionRevalidatesReadTargetsAndInventory() throws {
        let original = sample()
        for field in ["logicalSceneID", "targetNativeSceneID"] {
            let changed: ProbePhysicalOperationContextSample = try edit(original) { object in
                var rows = object["reads"] as! [[String: Any]]; rows[0][field] = "wrong"; object["reads"] = rows
            }
            XCTAssertNil(changed.ownerProjection, field)
        }
        let duplicate: ProbePhysicalOperationContextSample = try edit(original) { object in
            let rows = object["reads"] as! [[String: Any]]; object["reads"] = [rows[0], rows[0]]
        }
        XCTAssertNil(duplicate.ownerProjection)
    }

    func testSamplerSessionChangeAcrossWaitCannotBind() throws {
        let first = sample()
        var changed = sdkValues()
        for native in ["native-scene-A", "native-scene-B"] {
            changed[native] = try edit(changed[native]!) { $0["sessionID"] = "00000000-0000-0000-0000-000000000099" }
        }
        let second = sample(values: changed)
        XCTAssertNil(first.failure); XCTAssertNil(second.failure)
        XCTAssertNil(try binding(before: XCTUnwrap(first.ownerProjection), after: XCTUnwrap(second.ownerProjection)))
    }

    func testSamplerDirectReadsCannotSubstituteForMapperOwners() throws {
        let capture = sample(), owners = try XCTUnwrap(capture.ownerProjection)
        XCTAssertNil(try binding(signals: [], before: owners, after: owners))
        XCTAssertNotNil(try binding(signals: views(), before: owners, after: owners))
    }

}
