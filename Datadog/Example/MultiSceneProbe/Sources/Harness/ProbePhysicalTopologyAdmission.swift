/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation
import UIKit

/// Exact fixture profile for the existing inferred Operation scenario. This
/// prepares the contract only; input-idle and host transport remain separate.
internal struct ProbePhysicalOperationProfile: Codable, Equatable {
    static let scenarioID = "operations.cross-scene.lifecycle"
    static let receiptSuffix = ".operations-physical-admission.json"
    static let criticalInterval = 6...21
    static let inferenceMechanism = "debug-rum-ui-event-network-context"

    let sourceRevision: String
    let buildConfiguration: String
    let scenarioSHA256: String
    let inference: String

    static var steps: [ProbeStep] {
        let calls: [(ProbeStepKind, String, String, String)] = [
            (.startOperation, "scene-A", "cross-success", "operation-cross-success-start-a"),
            (.succeedOperation, "scene-B", "cross-success", "operation-cross-success-end-b"),
            (.startOperation, "scene-A", "cross-failure", "operation-cross-failure-start-a"),
            (.failOperation, "scene-B", "cross-failure", "operation-cross-failure-end-b"),
            (.startOperation, "scene-A", "parallel-alpha", "operation-parallel-alpha-start-a"),
            (.startOperation, "scene-B", "parallel-beta", "operation-parallel-beta-start-b"),
            (.succeedOperation, "scene-B", "parallel-beta", "operation-parallel-beta-end-b"),
            (.succeedOperation, "scene-A", "parallel-alpha", "operation-parallel-alpha-end-a")
        ]
        return [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-A", value: "operation-cross-home-a"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "rum-view:home#1"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-B", value: "operation-cross-home-b")
        ] + calls.flatMap { kind, scene, instance, marker in
            [ProbeStep(kind, scene: scene, value: instance),
             ProbeStep(.emitSceneContextMarker, scene: scene, value: marker)]
        }
    }

    static func make(scenario: ProbeScenario, sourceRevision: String, buildConfiguration: String) -> Self? {
        guard let canonical = ProbeScenarioCatalog.all.first(where: { $0.identifier == scenarioID }),
              scenario == canonical, scenario.identifier == scenarioID, scenario.steps == steps,
              scenario.trackingMode == .manual, scenario.layout == .stack,
              scenario.initialWindows == ["scene-A", "scene-B"],
              scenario.requiredCapabilities == [.multipleScenes, .simultaneousVisibleWindows],
              scenario.defaultRunMode == .clean,
              sourceRevision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              buildConfiguration == "Debug" else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(scenario) else { return nil }
        return Self(sourceRevision: sourceRevision, buildConfiguration: buildConfiguration,
                    scenarioSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                    inference: inferenceMechanism)
    }

    @MainActor
    static func ownerIdentities(_ scenes: [ProbePhysicalSceneObservation]) -> [String: [String]]? {
        guard ProbePhysicalTopologyAdmission.validateLive(scenes) == nil,
              scenes.allSatisfy({ !($0.windowIdentity ?? "").isEmpty && !($0.rootIdentity ?? "").isEmpty }),
              Set(scenes.compactMap(\.windowIdentity)).count == 2,
              Set(scenes.compactMap(\.rootIdentity)).count == 2 else { return nil }
        return Dictionary(uniqueKeysWithValues: scenes.map {
            ($0.logicalSceneID, [$0.nativeSceneID, String($0.generation), $0.windowIdentity ?? "", $0.rootIdentity ?? ""])
        })
    }

    /// Called before and after each exact step, and by the continuous observer.
    /// A failure is sticky, so later matching observations cannot hide drift.
    @MainActor
    struct Progress {
        let owners: [String: [String]]
        private(set) var nextIndex = criticalInterval.lowerBound
        private(set) var expectsAfter = false
        private(set) var failure: String?
        private(set) var complete = false

        init?(scenes: [ProbePhysicalSceneObservation]) {
            guard let owners = ownerIdentities(scenes) else { return nil }
            self.owners = owners
        }

        mutating func observe(_ scenes: [ProbePhysicalSceneObservation]) -> String? {
            if failure == nil && ownerIdentities(scenes) != owners {
                failure = "Operation scene, window or root owner changed"
            }
            return failure
        }

        mutating func check(index: Int, step: ProbeStep, after: Bool, scenes: [ProbePhysicalSceneObservation]) -> String? {
            if let reason = observe(scenes) { return reason }
            guard !complete, index == nextIndex, after == expectsAfter,
                  criticalInterval.contains(index), step == steps[index] else {
                failure = "Operation admission step is duplicate, late or changed"
                return failure
            }
            if after {
                complete = index == criticalInterval.upperBound
                nextIndex += 1
            }
            expectsAfter = !after
            return nil
        }
    }
}

internal struct ProbePhysicalSceneObservation: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let generation: UInt64
    let connected: Bool
    let activationState: String
    let hidden: Bool
    let alpha: Double
    let geometry: ProbeGeometry
    var windowIdentity: String? = nil
    var rootIdentity: String? = nil
}

internal struct ProbePhysicalTopologyObservation: Codable, Equatable {
    let nonce: String
    let captureID: String?
    let evidenceSHA256: String?
    let scenes: [ProbePhysicalSceneObservation]
}

internal struct ProbePhysicalAdmissionChallenge: Codable {
    let runID: String
    let scenarioID: String
    let processID: Int32
    let nonce: String
    let createdAtMilliseconds: Int64
    let observedAtMilliseconds: Int64
    let scenes: [ProbePhysicalSceneObservation]
}

internal struct ProbePhysicalAdmissionReceipt: Codable {
    var runID: String
    var scenarioID: String
    var processID: Int32
    var nonce: String
    var capturedAtMilliseconds: Int64
    var captureID: String
    var evidenceSHA256: String
    var nativeSceneIDs: [String: String]
    var generations: [String: UInt64]
}

/// Not accepted by the same-key file path or validator. The eventual host must
/// additionally bind release/input-idle, installed binaries and display proof.
internal struct ProbePhysicalOperationReceipt: Codable {
    var topology: ProbePhysicalAdmissionReceipt
    var profile: ProbePhysicalOperationProfile
    var owners: [String: [String]]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(topology: ProbePhysicalAdmissionReceipt, profile: ProbePhysicalOperationProfile, owners: [String: [String]]) {
        self.topology = topology
        self.profile = profile
        self.owners = owners
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        func requireKeys(_ actual: [Key], _ expected: Set<String>) throws {
            guard Set(actual.map(\.stringValue)) == expected else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                       debugDescription: "Unexpected Operation admission fields"))
            }
        }
        try requireKeys(values.allKeys, ["topology", "profile", "owners"])
        let topologyKey = Key(stringValue: "topology")
        let profileKey = Key(stringValue: "profile")
        try requireKeys(values.nestedContainer(keyedBy: Key.self, forKey: topologyKey).allKeys,
                        ["runID", "scenarioID", "processID", "nonce", "capturedAtMilliseconds",
                         "captureID", "evidenceSHA256", "nativeSceneIDs", "generations"])
        try requireKeys(values.nestedContainer(keyedBy: Key.self, forKey: profileKey).allKeys,
                        ["sourceRevision", "buildConfiguration", "scenarioSHA256", "inference"])
        topology = try values.decode(ProbePhysicalAdmissionReceipt.self, forKey: topologyKey)
        profile = try values.decode(ProbePhysicalOperationProfile.self, forKey: profileKey)
        owners = try values.decode([String: [String]].self, forKey: Key(stringValue: "owners"))
    }

    @MainActor
    func validate(profile expected: ProbePhysicalOperationProfile, challenge: ProbePhysicalAdmissionChallenge,
                  live: [ProbePhysicalSceneObservation], now: Int64) -> String? {
        guard profile == expected, challenge.scenarioID == ProbePhysicalOperationProfile.scenarioID,
              let original = ProbePhysicalOperationProfile.ownerIdentities(challenge.scenes),
              let current = ProbePhysicalOperationProfile.ownerIdentities(live),
              owners == original, owners == current else {
            return "Operation profile or owned window/root identity changed"
        }
        return ProbePhysicalTopologyAdmission.validate(topology, challenge: challenge, live: live, now: now)
    }
}

/// Fixture-only barrier. External display evidence establishes visibility;
/// live UIKit observations fence lifecycle/identity changes before mutation.
@MainActor
internal final class ProbePhysicalTopologyAdmission {
    static let scenarioID = "swiftui.coexistence.same-key-manual-two-scenes"
    private let runID: String
    private let registry: ProbeSceneRegistry
    private let recorder: ProbeEventRecorder
    private let directory: URL
    private let nonce = UUID().uuidString
    private var createdAt: Int64 = 0
    private var admitted: ProbePhysicalAdmissionReceipt?
    private var failure: String?
    private var monitor: Task<Void, Never>?

    init(runID: String, registry: ProbeSceneRegistry, recorder: ProbeEventRecorder, directory: URL) {
        self.runID = runID
        self.registry = registry
        self.recorder = recorder
        self.directory = directory
    }

    private var receiptURL: URL { directory.appendingPathComponent(runID + ".physical-admission.json") }
    private var challengeURL: URL { directory.appendingPathComponent(runID + ".physical-challenge.json") }
    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    static func validateLive(_ scenes: [ProbePhysicalSceneObservation]) -> String? {
        guard scenes.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              Set(scenes.map(\.nativeSceneID)).count == 2,
              scenes.allSatisfy({ !$0.nativeSceneID.isEmpty }) else { return "two distinct native scenes required" }
        guard scenes.allSatisfy({ $0.connected && !$0.hidden && $0.alpha.isFinite && $0.alpha > 0
            && ["foreground-active", "foreground-inactive"].contains($0.activationState)
            && [$0.geometry.x, $0.geometry.y, $0.geometry.width, $0.geometry.height].allSatisfy(\.isFinite)
            && $0.geometry.width > 0 && $0.geometry.height > 0 }) else { return "live visible foreground windows required" }
        return nil
    }

    static func validate(
        _ receipt: ProbePhysicalAdmissionReceipt,
        challenge: ProbePhysicalAdmissionChallenge,
        live: [ProbePhysicalSceneObservation],
        now: Int64
    ) -> String? {
        guard receipt.runID == challenge.runID, receipt.scenarioID == challenge.scenarioID,
              receipt.processID == challenge.processID, receipt.nonce == challenge.nonce else {
            return "stale run, process or nonce"
        }
        guard receipt.capturedAtMilliseconds >= challenge.createdAtMilliseconds,
              receipt.capturedAtMilliseconds <= now + 2_000,
              now - receipt.capturedAtMilliseconds <= 60_000 else { return "stale or future display evidence" }
        guard UUID(uuidString: receipt.captureID) != nil,
              receipt.evidenceSHA256.count == 64,
              receipt.evidenceSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            return "independent display capture identity missing"
        }
        if let reason = validateLive(live) { return reason }
        let identities = Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.nativeSceneID) })
        let generations = Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.generation) })
        guard receipt.nativeSceneIDs == identities, receipt.generations == generations,
              Dictionary(uniqueKeysWithValues: challenge.scenes.map { ($0.logicalSceneID, $0.nativeSceneID) }) == identities,
              Dictionary(uniqueKeysWithValues: challenge.scenes.map { ($0.logicalSceneID, $0.generation) }) == generations else {
            return "scene identity or generation changed"
        }
        return nil
    }

    private func observe() -> [ProbePhysicalSceneObservation] {
        ["scene-A", "scene-B"].compactMap { label in
            guard let handle = registry.handle(logicalSceneID: label),
                  let window = registry.window(for: handle), let scene = window.windowScene,
                  let geometry = ProbeScenePresentation.capture(window: window).geometry else { return nil }
            return .init(logicalSceneID: label, nativeSceneID: scene.session.persistentIdentifier,
                         generation: handle.disconnectGeneration,
                         connected: scene.session.persistentIdentifier == handle.nativeSceneID
                            && UIApplication.shared.connectedScenes.contains(scene),
                         activationState: ProbeSceneActivationState(scene.activationState).rawValue,
                         hidden: window.isHidden, alpha: Double(window.alpha), geometry: geometry)
        }
    }

    private func record(_ name: String, scenes: [ProbePhysicalSceneObservation], result: ProbeSemanticResultState, reason: String? = nil) {
        recorder.record(ProbeSignal(kind: .assertion, name: name,
            physicalTopology: .init(nonce: nonce, captureID: admitted?.captureID,
                                   evidenceSHA256: admitted?.evidenceSHA256, scenes: scenes),
            result: result, reason: reason))
    }

    private func checkAdmitted() -> String? {
        if let failure { return failure }
        guard let admitted else { return "physical admission missing" }
        let live = observe()
        if let reason = Self.validateLive(live) { return reason }
        guard Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.nativeSceneID) }) == admitted.nativeSceneIDs,
              Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.generation) }) == admitted.generations else {
            return "admitted scene identity or generation changed"
        }
        if FileManager.default.fileExists(atPath: receiptURL.path) { return "physical admission receipt reused" }
        return nil
    }

    func check(index: Int, step: ProbeStep, after: Bool) async -> String? {
        guard (6...16).contains(index) else { return nil }
        if admitted == nil && failure == nil {
            guard index == 6 && !after else { return "physical admission arrived after first mutation" }
            createdAt = now
            let original = observe()
            do {
                for _ in 0..<1_200 {
                    let live = observe()
                    let challenge = ProbePhysicalAdmissionChallenge(
                        runID: runID, scenarioID: Self.scenarioID, processID: ProcessInfo.processInfo.processIdentifier,
                        nonce: nonce, createdAtMilliseconds: createdAt, observedAtMilliseconds: now, scenes: live)
                    try JSONEncoder().encode(challenge).write(to: challengeURL, options: .atomic)
                    if FileManager.default.fileExists(atPath: receiptURL.path) {
                        let bytes = try Data(contentsOf: receiptURL)
                        guard bytes.count <= 16_384 else { return "oversized admission receipt" }
                        let receipt = try JSONDecoder().decode(ProbePhysicalAdmissionReceipt.self, from: bytes)
                        let initial = ProbePhysicalAdmissionChallenge(
                            runID: runID, scenarioID: Self.scenarioID, processID: challenge.processID,
                            nonce: nonce, createdAtMilliseconds: createdAt, observedAtMilliseconds: now, scenes: original)
                        if let reason = Self.validate(receipt, challenge: initial, live: live, now: now) {
                            failure = reason
                            break
                        }
                        admitted = receipt
                        try FileManager.default.removeItem(at: receiptURL)
                        record("physical-topology-admitted", scenes: live, result: .pass)
                        monitor = Task { @MainActor [weak self] in
                            while !Task.isCancelled {
                                guard let self else { return }
                                if let reason = self.checkAdmitted() {
                                    self.failure = reason
                                    self.record("physical-topology-lost", scenes: self.observe(), result: .inconclusive, reason: reason)
                                    return
                                }
                                try? await Task.sleep(nanoseconds: 50_000_000)
                            }
                        }
                        break
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            } catch {
                failure = "physical admission file or wait failed"
            }
            if admitted == nil && failure == nil { failure = "timed out before physical topology admission" }
        }
        if let reason = checkAdmitted() { failure = reason }
        record("physical-topology-\(after ? "after" : "before")-\(index)", scenes: observe(),
               result: failure == nil ? .pass : .inconclusive, reason: failure)
        if failure != nil || (index == 16 && after) {
            monitor?.cancel()
            monitor = nil
        }
        return failure
    }
}
