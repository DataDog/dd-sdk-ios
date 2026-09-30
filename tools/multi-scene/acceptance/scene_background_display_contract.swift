// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

/// Marker identity only. Rendering and decoded pixels never grant SDK work.
@MainActor
internal enum ProbeSceneBackgroundDisplayContract {
    typealias Control = ProbeSceneBackgroundControl
    struct Owner: Codable, Equatable {
        let logicalSceneID: String
        let nativeSceneID: String
        let sceneIdentity: String
        let generation: UInt64
        let windowIdentity: String
        let rootIdentity: String
        let observerIdentity: String
    }
    struct Descriptor: Codable {
        let schemaVersion: Int
        let request: Data
        let witness: Data
        let token: String
        let owners: [Owner]
        let contextSHA256: String
        let requiredScenes: [String]
        let payloads: [String: [String: String]]
    }
    private struct Context: Encodable {
        let requestSHA256: String
        let witnessSHA256: String
        let ownersSHA256: String
        let token: String
    }
    private struct Witness: Decodable {
        struct NativeOwner: Decodable {
            let logicalSceneID: String
            let nativeSceneID: String
            let sceneIdentity: String
            let generation: UInt64
            let windowIdentity: String
            let rootIdentity: String
        }
        struct Input: Decodable { let logicalSceneID: String; let observerIdentity: String }
        struct Continuity: Decodable { let owners: [NativeOwner]; let failure: String? }
        struct Snapshot: Decodable {
            let continuity: Continuity
            let input: [Input]
            let applicationActive: Bool
            let failure: String?
        }
        let schemaVersion: Int
        let runID: String
        let scenarioID: String
        let profile: String
        let snapshot: Snapshot
    }
    enum Failure: Error { case identity, owner, sequence, surface }

    static func make(request raw: Data, witness rawWitness: Data, identity: Control.Identity,
                     token suppliedToken: String? = nil) throws -> Descriptor {
        guard raw.count <= Control.maximumBytes, rawWitness.count <= 16_777_216 else { throw Failure.identity }
        let request = try JSONDecoder().decode(ProbeSceneBackgroundPhase.Request.self, from: raw)
        // The existing host-issued command is single-use in the phase transport.
        let token = suppliedToken ?? request.commandID
        let phase = request.challenge
        let names = ProbeSceneBackgroundPhase.names + ["collection-seal"]
        guard try Control.encode(request) == raw, phase.identity == identity,
              identity.scenarioID == Control.scenarioID, identity.profile == Control.profile,
              names.indices.contains(phase.phase), names[phase.phase] == phase.name,
              phase.maximumInspections == 24,
              UUID(uuidString: phase.challengeID)?.uuidString.lowercased() == phase.challengeID,
              token == request.commandID, request.operation == "inspect", request.sequence > 0,
              UUID(uuidString: request.commandID)?.uuidString.lowercased() == request.commandID,
              Control.digest(request.previousReplySHA256), request.inspectedReplySHA256 == nil,
              request.displayReceiptSHA256 == nil, request.semanticProof == nil else { throw Failure.identity }
        if phase.phase == 3 {
            guard let consumed = phase.consumedPhaseReplies, consumed.count == 3,
                  Set(consumed).count == 3, consumed.allSatisfy(Control.digest),
                  let invocation = phase.finalInvocationSequence, invocation > 0 else { throw Failure.identity }
        } else if phase.consumedPhaseReplies != nil || phase.finalInvocationSequence != nil {
            throw Failure.identity
        }
        let native = try JSONDecoder().decode(Witness.self, from: rawWitness)
        let snapshot = native.snapshot, labels = ["scene-A", "scene-B"]
        guard native.schemaVersion == 1, native.runID == identity.runID,
              native.scenarioID == identity.scenarioID, native.profile == identity.profile,
              snapshot.applicationActive, snapshot.failure == nil, snapshot.continuity.failure == nil,
              snapshot.continuity.owners.map(\.logicalSceneID) == labels,
              snapshot.input.map(\.logicalSceneID) == labels else { throw Failure.owner }
        let owners = zip(snapshot.continuity.owners, snapshot.input).map { owner, input in
            Owner(logicalSceneID: owner.logicalSceneID, nativeSceneID: owner.nativeSceneID,
                  sceneIdentity: owner.sceneIdentity, generation: owner.generation,
                  windowIdentity: owner.windowIdentity, rootIdentity: owner.rootIdentity,
                  observerIdentity: input.observerIdentity)
        }
        for values in [owners.map(\.nativeSceneID), owners.map(\.sceneIdentity), owners.map(\.windowIdentity),
                       owners.map(\.rootIdentity), owners.map(\.observerIdentity)] {
            guard values.allSatisfy({ !$0.isEmpty }), Set(values).count == 2 else { throw Failure.owner }
        }
        let context = Context(requestSHA256: Control.sha(raw), witnessSHA256: Control.sha(rawWitness),
                              ownersSHA256: Control.sha(try Control.encode(owners)), token: token)
        let contextSHA = Control.sha(try Control.encode(context))
        let required = phase.phase == 1 ? ["scene-B"] : labels
        var payloads: [String: [String: String]] = [:]
        for owner in owners where required.contains(owner.logicalSceneID) {
            let prefix = ["DDH10", "1", contextSHA, owner.logicalSceneID,
                          Control.sha(try Control.encode(owner))].joined(separator: "|")
            payloads[owner.logicalSceneID] = ["owner": prefix + "|OWNER", "phase": prefix + "|" + phase.name]
        }
        return Descriptor(schemaVersion: 1, request: raw, witness: rawWitness, token: token, owners: owners,
                          contextSHA256: contextSHA, requiredScenes: required, payloads: payloads)
    }
}
