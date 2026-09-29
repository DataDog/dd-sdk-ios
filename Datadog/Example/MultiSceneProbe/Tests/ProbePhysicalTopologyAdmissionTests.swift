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
