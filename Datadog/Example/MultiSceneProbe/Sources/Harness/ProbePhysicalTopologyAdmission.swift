/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

internal struct ProbePhysicalSceneObservation: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let generation: UInt64
    let connected: Bool
    let activationState: String
    let hidden: Bool
    let alpha: Double
    let geometry: ProbeGeometry
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
