// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

/// Complete recorder snapshots, rather than the bounded observer stream, are the
/// primary capture. Each Data value is an actual encoded row, retained verbatim.
@MainActor
internal final class ProbeSceneBackgroundCapture {
    typealias Control = ProbeSceneBackgroundControl
    struct Snapshot: Codable, Equatable { let signals: [Data]; let terminal: Data? }
    struct Capture: Codable {
        let identity: Control.Identity
        let sequence: Int
        let boundary: String
        let before: Data
        let snapshot: Snapshot
        let after: Data
    }
    struct Reference: Codable, Equatable {
        let name: String
        let sha256: String
        let bytes: Int
    }
    struct HostProof: Codable {
        let identity: Control.Identity
        let captureSHA256: String
        let oracleSourceSHA256: String
        let displayReceiptSHA256: String
        let consumedPhaseReplies: [String]
        let finalInvocationSequence: UInt64
        let localResult: Data
    }
    struct Seal: Codable {
        let identity: Control.Identity
        let inspected: Reference
        let fresh: Reference
        let extensionRows: Reference
        let extensionFirstSequence: UInt64?
        let extensionLastSequence: UInt64?
        let semanticProof: Data
        let challenge: ProbeSceneBackgroundPhase.Challenge
        let displayReceiptSHA256: String
        let state: String
    }
    struct Context: Codable, Equatable {
        let sessionID: String?
        let viewID: String?
        let viewName: String?
        let viewActive: Bool?
        let viewDocumentVersion: Int64?
    }
    struct Semantic: Codable, Equatable {
        let logicalSceneID: String
        let nativeSceneID: String?
        let screen: String?
    }
    struct Source: Codable { let logicalSceneID: String?; let nativeSceneID: String?; let phase: String? }
    struct Row: Decodable {
        let schemaVersion: Int
        let sequence: UInt64
        let runID: String
        let scenarioID: String
        let kind: String
        let evidenceSource: String
        let name: String?
        let result: String?
        let eventID: String?
        let rumContext: Context?
        let semanticContext: Semantic?
        let sourceContext: Source?
    }
    struct View: Equatable {
        let session: String
        let name: String?
        let owner: Semantic
        var documents: [Int64: Bool]
        var active: Bool { documents[documents.keys.max() ?? 0] == true }
    }
    struct Work: Codable, Equatable {
        let kind: String
        let event_id: String
        let session_id: String
        let view_id: String
        let phase: String
        let source_scene: String
    }
    struct LocalResult: Decodable {
        let state: String
        let profile: String
        let session_id: String
        let marker_owners: [String: String]
        let work: [Work]
    }
    enum Failure: Error { case identity, file, prefix, terminal, proof, owner, work, repeated }
    static let markers = ["A.before-background", "B.before-background", "B.while-A-background",
                          "A.after-foreground", "B.after-A-foreground"]
    static let maximumBytes = 16_777_216
    let identity: Control.Identity
    private let directory: URL
    private let snapshot: () throws -> Snapshot
    private let witness: () throws -> Data
    private let oracleSourceSHA256: String
    private var sequence = 0
    private var published: [String: String] = [:]
    private var sealedSnapshot: Snapshot?
    private(set) var sealed = false

    init(directory: URL, identity: Control.Identity, oracleSourceSHA256: String,
         snapshot: @escaping () throws -> Snapshot, witness: @escaping () throws -> Data) throws {
        guard Control.digest(oracleSourceSHA256), !FileManager.default.fileExists(atPath: directory.path) else {
            throw Failure.identity
        }
        self.identity = identity; self.directory = directory; self.oracleSourceSHA256 = oracleSourceSHA256
        self.snapshot = snapshot; self.witness = witness
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    private func verifyDirectory() throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.file }
    }

    @discardableResult
    private func persist(_ raw: Data, label: String) throws -> Reference {
        try verifyDirectory()
        guard raw.count <= Self.maximumBytes else { throw Failure.file }
        let hash = Control.sha(raw), name = label + "-" + hash + ".json"
        let url = directory.appendingPathComponent(name)
        if let original = published[name] {
            guard original == hash else { throw Failure.file }
        } else {
            guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.file }
            try raw.write(to: url, options: .withoutOverwriting)
            published[name] = hash
        }
        let reference = Reference(name: name, sha256: hash, bytes: raw.count)
        guard try read(reference) == raw else { throw Failure.file }
        return reference
    }

    private func read(_ reference: Reference) throws -> Data {
        try verifyDirectory()
        guard reference.bytes >= 0, reference.bytes <= Self.maximumBytes, Control.digest(reference.sha256),
              reference.name.range(of: "^[a-z-]+-[a-f0-9]{64}\\.json$", options: .regularExpression) != nil,
              let original = published[reference.name] else { throw Failure.file }
        let url = directory.appendingPathComponent(reference.name)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == reference.bytes else { throw Failure.file }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let bytes = try file.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard original == reference.sha256, bytes.count == reference.bytes, Control.sha(bytes) == reference.sha256 else { throw Failure.file }
        return bytes
    }

    func rows(_ value: Snapshot) throws -> [Row] {
        guard value.signals.count <= 16_384 else { throw Failure.prefix }
        return try value.signals.enumerated().map { index, raw in
            let row = try JSONDecoder().decode(Row.self, from: raw)
            guard row.schemaVersion == 5, row.sequence == UInt64(index + 1), row.runID == identity.runID,
                  row.scenarioID == identity.scenarioID else { throw Failure.prefix }
            return row
        }
    }

    /// Called with the actual signal returned by the recorder. A failed write
    /// propagates to the synchronous dispatcher before it can invoke SDK work.
    func publish(_ raw: Data) throws {
        let row = try JSONDecoder().decode(Row.self, from: raw)
        guard row.schemaVersion == 5, row.runID == identity.runID, row.scenarioID == identity.scenarioID,
              row.sequence > 0, row.kind == "assertion", row.evidenceSource == "probe",
              row.name?.hasPrefix("h10.") == true else { throw Failure.identity }
        try persist(raw, label: "dispatch")
    }

    func inspect(boundary: String) throws -> Data {
        let before = try witness(), current = try snapshot(), after = try witness()
        _ = try rows(current)
        if let sealedSnapshot {
            guard current.signals.count >= sealedSnapshot.signals.count,
                  Array(current.signals.prefix(sealedSnapshot.signals.count)) == sealedSnapshot.signals else { throw Failure.prefix }
        }
        sequence += 1
        let capture = Capture(identity: identity, sequence: sequence, boundary: boundary,
                              before: before, snapshot: current, after: after)
        return try Control.encode(persist(Control.encode(capture), label: "capture"))
    }

    func capture(_ referenceBytes: Data) throws -> (Reference, Capture) {
        let reference = try JSONDecoder().decode(Reference.self, from: referenceBytes)
        guard try Control.encode(reference) == referenceBytes else { throw Failure.file }
        let capture = try JSONDecoder().decode(Capture.self, from: read(reference))
        guard capture.identity == identity else { throw Failure.identity }
        _ = try rows(capture.snapshot)
        return (reference, capture)
    }

    func views(_ value: Snapshot) throws -> [String: View] {
        var result: [String: View] = [:]
        for row in try rows(value) where row.kind == "rum-view-snapshot" {
            guard row.evidenceSource == "rum-mapper", let context = row.rumContext,
                  let id = context.viewID, !id.isEmpty, let session = context.sessionID, !session.isEmpty,
                  let active = context.viewActive, let version = context.viewDocumentVersion, version > 0,
                  let owner = row.semanticContext, ["scene-A", "scene-B"].contains(owner.logicalSceneID),
                  owner.screen == "home", let native = owner.nativeSceneID, !native.isEmpty else { throw Failure.owner }
            if var previous = result[id] {
                guard previous.session == session, previous.owner == owner, previous.name == context.viewName,
                      previous.documents[version] == nil else { throw Failure.owner }
                previous.documents[version] = active; result[id] = previous
            } else { result[id] = View(session: session, name: context.viewName, owner: owner, documents: [version: active]) }
        }
        guard Set(result.values.map(\.session)).count <= 1 else { throw Failure.owner }
        return result
    }

    func currentOwners(_ value: Snapshot) throws -> [String: String] {
        var owners: [String: String] = [:]
        for (id, view) in try views(value) where view.active {
            guard owners.updateValue(id, forKey: view.owner.logicalSceneID) == nil else { throw Failure.owner }
        }
        return owners
    }

    private func positive(_ value: Snapshot, result: LocalResult) throws {
        let rows = try rows(value), views = try views(value)
        guard value.terminal == nil, result.state == "PASS_LOCAL_COMPONENT_ONLY", result.profile == identity.profile,
              Set(result.marker_owners.keys) == Set(Self.markers), result.work.count == 10,
              !rows.contains(where: { $0.kind == "rum-error" || ($0.result != nil && $0.result != "PASS") }) else {
            throw Failure.proof
        }
        let actual = try rows.filter { ["rum-action", "rum-resource"].contains($0.kind) }.map { row -> Work in
            guard let name = row.name, Self.markers.contains(name), row.evidenceSource == "rum-mapper",
                  let id = row.eventID, !id.isEmpty, let context = row.rumContext,
                  let viewID = context.viewID, let view = views[viewID], let session = context.sessionID,
                  session == result.session_id, session == view.session, let source = row.sourceContext,
                  source.phase == name, let scene = source.logicalSceneID,
                  scene == (name.hasPrefix("A.") ? "scene-A" : "scene-B"),
                  view.owner.logicalSceneID == scene, source.nativeSceneID == view.owner.nativeSceneID,
                  result.marker_owners[name] == viewID else { throw Failure.work }
            return Work(kind: String(row.kind.dropFirst(4)), event_id: id, session_id: session,
                        view_id: viewID, phase: name, source_scene: scene)
        }
        guard actual == result.work, Set(actual.map { $0.kind + ":" + $0.event_id }).count == 10,
              Self.markers.allSatisfy({ name in actual.filter { $0.phase == name }.map(\.kind).sorted() == ["action", "resource"] }),
              let a0 = result.marker_owners[Self.markers[0]], let b = result.marker_owners[Self.markers[1]],
              let a1 = result.marker_owners[Self.markers[3]], Set([a0, b, a1]).count == 3,
              result.marker_owners[Self.markers[2]] == b, result.marker_owners[Self.markers[4]] == b,
              views[a0]?.active == false, views[a1]?.active == true, views[b]?.active == true,
              try currentOwners(value) == ["scene-A": a1, "scene-B": b] else { throw Failure.work }
    }

    func seal(inspected: Data, proof: Data, display: String, challenge: ProbeSceneBackgroundPhase.Challenge,
              validateNative: (Data) throws -> Void) throws -> Data {
        guard !sealed, sealedSnapshot == nil else { throw Failure.repeated }
        let (reference, previous) = try capture(inspected)
        let approval = try JSONDecoder().decode(HostProof.self, from: proof)
        guard try Control.encode(approval) == proof, approval.identity == identity,
              approval.captureSHA256 == reference.sha256, approval.oracleSourceSHA256 == oracleSourceSHA256,
              approval.displayReceiptSHA256 == display, Control.digest(display), challenge.identity == identity,
              challenge.name == "collection-seal", challenge.consumedPhaseReplies == approval.consumedPhaseReplies,
              approval.consumedPhaseReplies.count == 3, challenge.finalInvocationSequence == approval.finalInvocationSequence,
              try rows(previous.snapshot).contains(where: { $0.sequence == approval.finalInvocationSequence
                && $0.name == "h10.invoke.B.after-A-foreground" && $0.result == "PASS" }) else { throw Failure.proof }
        let result = try JSONDecoder().decode(LocalResult.self, from: approval.localResult)
        try positive(previous.snapshot, result: result)
        let freshReferenceBytes = try inspect(boundary: "seal")
        let (freshReference, fresh) = try capture(freshReferenceBytes)
        guard fresh.snapshot.terminal == nil, fresh.snapshot.signals.count >= previous.snapshot.signals.count,
              Array(fresh.snapshot.signals.prefix(previous.snapshot.signals.count)) == previous.snapshot.signals else {
            throw Failure.prefix
        }
        try validateNative(fresh.before); try validateNative(fresh.after)
        let oldViews = try views(previous.snapshot), newViews = try views(fresh.snapshot)
        guard Set(oldViews.keys) == Set(newViews.keys), oldViews.allSatisfy({ key, old in
            guard let new = newViews[key] else { return false }
            return old.session == new.session && old.owner == new.owner && old.name == new.name && old.active == new.active
        }) else { throw Failure.owner }
        let extra = Array(fresh.snapshot.signals.dropFirst(previous.snapshot.signals.count))
        let extraRows = Array(try rows(fresh.snapshot).dropFirst(previous.snapshot.signals.count))
        guard !extraRows.contains(where: { ["rum-action", "rum-resource", "rum-error"].contains($0.kind)
            || ($0.result != nil && $0.result != "PASS") || $0.name?.hasPrefix("h10.") == true }) else { throw Failure.work }
        try positive(fresh.snapshot, result: result)
        let extensionReference = try persist(Control.encode(extra), label: "extension")
        let receipt = Seal(identity: identity, inspected: reference, fresh: freshReference,
            extensionRows: extensionReference, extensionFirstSequence: extraRows.first?.sequence,
            extensionLastSequence: extraRows.last?.sequence, semanticProof: proof, challenge: challenge,
            displayReceiptSHA256: display, state: "SEALED_PREFIX_HOST_REVALIDATION_REQUIRED")
        let written = try persist(Control.encode(receipt), label: "seal")
        sealedSnapshot = fresh.snapshot; sealed = true
        return try Control.encode(written)
    }
}
