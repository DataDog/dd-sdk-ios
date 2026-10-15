/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import CoreImage
import CryptoKit

@MainActor
internal protocol ProbeOperationDisplayBoundary: AnyObject {
    var hasStarted: Bool { get }
    func begin() throws
    func validate() throws
    func pollRunRequest() throws
    func consumeRun(_ raw: Data) throws
    func seal(_ finalObservationSHA256: String) throws
    func pollFinalProof() throws -> Bool
    func finish(context: ProbePhysicalOperationContextSample, observationSHA256: String) throws -> [String: String]
    func retire()
}

/// Fixture-only phase and host-proof contract. Pixels alone never authorize SDK work.
@MainActor
internal final class ProbePhysicalOperationDisplay: ProbeOperationDisplayBoundary {
    enum Failure: Error { case identity, ownership, surface, sequence, proof, publication, expired }
    enum Phase: String, Codable { case start = "START", run = "RUN", final = "FINAL" }
    struct Binding: Codable, Equatable {
        let logicalSceneID: String
        let nativeSceneID: String
        let generation: UInt64
        let windowIdentity: String
        let rootIdentity: String
    }
    struct Reference: Codable, Equatable {
        let path: String
        let sha256: String
        var valid: Bool { path.hasPrefix("/") && Self.isDigest(sha256) }
        private static func isDigest(_ value: String) -> Bool {
            value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        }
    }
    struct Blob: Codable {
        let bytes: Data
        let sha256: String
        func decoded<T: Decodable>(_ type: T.Type) throws -> T {
            guard bytes.count <= 65_536, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw Failure.proof }
            return try JSONDecoder().decode(type, from: bytes)
        }
    }
    struct Manifest: Decodable {
        let schemaVersion: Int
        let kind: String
        let decoderSource: Reference
        let executable: Reference
        let invocation: Reference
        let process: Reference
        let raw: Reference
        let decoder: Reference
        let frames: Reference
        let nativeAcceptance: Bool
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", decoderSource = "decoder_source", nativeAcceptance = "native_acceptance"
            case kind, executable, invocation, process, raw, decoder, frames
        }
    }
    struct DecoderReceipt: Decodable {
        let schemaVersion: Int
        let state: String
        let kind: String
        let readerState: String
        let nativeAcceptance: Bool
        let inputSHA256: String
        let framesSHA256: String
        let frameCount: Int
        let revision: Int
        let trackCount: Int?
        let decodedOutput: Bool?
        let pixelFormat: UInt32?
    }
    struct ProcessReceipt: Decodable {
        let returncode: Int?
        let timedOut: Bool
        enum CodingKeys: String, CodingKey { case returncode, timedOut = "timed_out" }
    }
    struct Invocation: Decodable {
        let argv: [String]
        let binary: Reference
        let decoderSource: Reference
        let raw: Reference
        let nativeAcceptance: Bool
        enum CodingKeys: String, CodingKey {
            case argv, binary, raw
            case decoderSource = "decoder_source", nativeAcceptance = "native_acceptance"
        }
    }
    struct Media: Codable {
        let reference: Reference
        let manifest: Blob
        let decoder: Blob
        let invocation: Blob
        let process: Blob

        func validate(kind: String, sourceSHA256: String, binarySHA256: String) throws -> Manifest {
            let value = try manifest.decoded(Manifest.self)
            let result = try decoder.decoded(DecoderReceipt.self)
            let command = try invocation.decoded(Invocation.self)
            let execution = try process.decoded(ProcessReceipt.self)
            guard reference.valid, reference.sha256 == manifest.sha256,
                  URL(fileURLWithPath: reference.path).lastPathComponent == "manifest.json",
                  value.schemaVersion == 1, value.kind == kind, !value.nativeAcceptance,
                  [value.decoderSource, value.executable, value.invocation, value.process,
                   value.raw, value.decoder, value.frames].allSatisfy({ $0.valid }),
                  value.decoderSource.sha256 == sourceSHA256, value.executable.sha256 == binarySHA256,
                  value.decoder.sha256 == decoder.sha256, value.invocation.sha256 == invocation.sha256,
                  value.process.sha256 == process.sha256,
                  result.schemaVersion == 1, result.state == "DECODED", result.kind == kind,
                  result.readerState == "completed", !result.nativeAcceptance, result.revision == 3,
                  result.inputSHA256 == value.raw.sha256, result.framesSHA256 == value.frames.sha256,
                  result.frameCount > 0, result.frameCount <= 36_000,
                  kind != "IMAGE" || result.frameCount == 1,
                  kind != "MOVIE" || (result.trackCount == 1 && result.decodedOutput == true
                      && result.pixelFormat == 1_111_970_369),
                  execution.returncode == 0, !execution.timedOut,
                  !command.nativeAcceptance, command.binary == value.executable,
                  command.decoderSource == value.decoderSource, command.raw == value.raw else { throw Failure.proof }
            let folder = URL(fileURLWithPath: reference.path).deletingLastPathComponent()
            guard command.argv == [value.executable.path, kind.lowercased(), value.raw.path,
                                    folder.appendingPathComponent("decoded").path],
                  value.invocation.path == folder.appendingPathComponent("invocation.json").path,
                  value.process.path == folder.appendingPathComponent("process.json").path,
                  value.decoder.path == folder.appendingPathComponent("decoded/decoder.json").path,
                  value.frames.path == folder.appendingPathComponent("decoded/frames.jsonl").path,
                  URL(fileURLWithPath: value.raw.path).deletingLastPathComponent() == folder else { throw Failure.proof }
            return value
        }
    }
    struct Proof: Codable {
        let schemaVersion: Int
        let identity: ProbePhysicalOperationChannelIdentity
        let nonce: String
        let phase: Phase
        let requestID: String
        let nativeReceiptSHA256: String
        // The exact bit pattern binds the existing deadline without cross-language decimal re-encoding.
        let deadlineBits: String
        let owners: [String: String]
        let anchors: [String: Media]
        let movie: Media?
        let assessment: Blob?
    }
    struct Receipt: Codable {
        let schemaVersion: Int
        let identity: ProbePhysicalOperationChannelIdentity
        let nonce: String
        let phase: Phase
        let sequence: Int
        let deadlineBits: String
        let bindings: [String: Binding]
        let bindingSHA256: [String: String]
        let surfaces: [String: [String: ProbeGeometry]]
        let geometryScope: String
        let previousReceiptSHA256: String?
        let causeSHA256: String?
        let nativeAcceptance: Bool
    }

    @MainActor final class Surface {
        private final class Container: UIView {
            let owner = UIImageView()
            let phase = UIImageView()
            private(set) var validGeometry = false
            private var expectedFrames: [CGRect] = []
            var framesUnchanged: Bool {
                let scale = traitCollection.displayScale
                guard scale.isFinite, scale > 0, expectedFrames.count == 2 else { return false }
                func pixels(_ rect: CGRect) -> [CGFloat] {
                    [rect.minX, rect.minY, rect.width, rect.height].map { ($0 * scale).rounded() }
                }
                return zip([owner, phase], expectedFrames).allSatisfy { image, expected in
                    pixels(image.frame).allSatisfy(\.isFinite) && pixels(image.frame) == pixels(expected)
                        && image.transform.isIdentity && CATransform3DIsIdentity(image.layer.transform)
                }
            }
            override func layoutSubviews() {
                super.layoutSubviews()
                let scale = traitCollection.displayScale
                let safe = bounds.inset(by: safeAreaInsets).insetBy(dx: 12, dy: 12)
                validGeometry = scale.isFinite && scale > 0 && safe.width.isFinite && safe.height.isFinite
                    && safe.width >= 176 && safe.height >= 360
                expectedFrames = []
                guard validGeometry else { return }
                for (index, image) in [owner, phase].enumerated() {
                    guard let grid = image.image?.size.width, grid.isFinite, grid > 0 else {
                        validGeometry = false; return
                    }
                    let pixels = floor(176 * scale / grid) * grid
                    let x = floor((safe.maxX - pixels / scale) * scale) / scale
                    let y = ceil((safe.minY + CGFloat(index) * 184) * scale) / scale
                    image.frame = CGRect(x: x, y: y, width: pixels / scale, height: pixels / scale)
                    expectedFrames.append(image.frame)
                }
            }
        }
        weak var window: UIWindow?
        weak var root: UIViewController?
        weak var scene: UIWindowScene?
        private let container = Container()
        var owner: UIImageView { container.owner }
        var phase: UIImageView { container.phase }
        var view: UIView { container }
        private var frozenOwnerPixels: [CGFloat]?
        private var ownerPixels: [CGFloat]? {
            let scale = container.traitCollection.displayScale
            let values = [container.frame, container.bounds, owner.frame].flatMap {
                [$0.minX, $0.minY, $0.width, $0.height]
            }
            guard scale.isFinite, scale > 0, values.allSatisfy(\.isFinite) else { return nil }
            return values.map { ($0 * scale).rounded() }
        }
        var validGeometry: Bool {
            container.validGeometry && container.framesUnchanged && ownerPixels != nil
                && (frozenOwnerPixels == nil || frozenOwnerPixels == ownerPixels)
        }
        func freezeGeometry() throws {
            guard validGeometry, let pixels = ownerPixels else { throw Failure.surface }
            frozenOwnerPixels = pixels
        }
        let binding: Binding
        var ownerImage: UIImage
        var phaseImage: UIImage

        init(window: UIWindow, binding: Binding, ownerImage: UIImage, phaseImage: UIImage) {
            self.window = window; self.root = window.rootViewController; self.scene = window.windowScene
            self.binding = binding; self.ownerImage = ownerImage; self.phaseImage = phaseImage
            container.isUserInteractionEnabled = false
            container.frame = window.bounds
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            for image in [owner, phase] {
                image.isUserInteractionEnabled = false; image.contentMode = .scaleAspectFit
                image.backgroundColor = .white; image.layer.magnificationFilter = .nearest
                image.layer.minificationFilter = .nearest; container.addSubview(image)
            }
            owner.image = ownerImage; phase.image = phaseImage
            window.addSubview(container)
        }
        func validate(in owned: UIWindow) throws {
            guard owned === window, owned.windowScene === scene, owned.rootViewController === root,
                  validGeometry, view.superview === owned, view.window === owned,
                  !view.isHidden, view.alpha == 1, !view.isUserInteractionEnabled,
                  view.transform.isIdentity, CATransform3DIsIdentity(view.layer.transform),
                  owner.image === ownerImage, phase.image === phaseImage,
                  [owner, phase].allSatisfy({ $0.superview === view && !$0.isHidden && $0.alpha == 1 }) else {
                throw Failure.surface
            }
        }
        func layout() throws {
            container.setNeedsLayout(); container.layoutIfNeeded()
            guard validGeometry else { throw Failure.surface }
        }
        func geometry() -> [String: ProbeGeometry] {
            func record(_ rect: CGRect) -> ProbeGeometry {
                .init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            }
            return ["containerInWindowPoints": record(view.frame),
                    "ownerInWindowPoints": record(owner.convert(owner.bounds, to: window)),
                    "phaseInWindowPoints": record(phase.convert(phase.bounds, to: window))]
        }
    }

    let nonce: String
    private let channel: ProbePhysicalOperationChannel
    private let registry: ProbeSceneRegistry
    private let deadline: TimeInterval
    private let snapshot: () -> ProbePhysicalInputSnapshot
    private let now: () -> TimeInterval
    private let decoderSourceSHA256: String
    private let decoderBinarySHA256: String
    private var surfaces: [String: Surface] = [:]
    private var digests: [String: String] = [:]
    private var proofChain: ProofChain?
    private var latestReceipt: Data?
    private var publishedArtifacts: [String: String] = [:]
    private var sealedObservationSHA256: String?
    private var runRequestSHA256: String?
    var hasStarted: Bool { current != nil }
    private(set) var current: Phase?
    private(set) var runProofSHA256: String?
    private(set) var finalProofSHA256: String?
    private(set) var invalid = false

    init(channel: ProbePhysicalOperationChannel, registry: ProbeSceneRegistry, deadline: TimeInterval,
         nonce: String, decoderSourceSHA256: String, decoderBinarySHA256: String,
         snapshot: @escaping () -> ProbePhysicalInputSnapshot,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) throws {
        guard channel.identity.schemaVersion == 2, channel.identity.setupProfile != nil,
              UUID(uuidString: channel.identity.runID)?.uuidString.lowercased() == channel.identity.runID,
              UUID(uuidString: nonce)?.uuidString.lowercased() == nonce,
              deadline.isFinite, now() < deadline,
              [decoderSourceSHA256, decoderBinarySHA256].allSatisfy(Self.digest) else { throw Failure.identity }
        self.channel = channel; self.registry = registry; self.deadline = deadline; self.nonce = nonce
        self.decoderSourceSHA256 = decoderSourceSHA256; self.decoderBinarySHA256 = decoderBinarySHA256
        self.snapshot = snapshot; self.now = now
    }
    private static func digest(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }
    private static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    private var deadlineBits: String { String(deadline.bitPattern, radix: 16) }
    private func live() throws {
        guard !invalid, channel.failure == nil, now() < deadline, !Task.isCancelled else { throw Failure.expired }
    }
    private func terminal<T>(_ work: () throws -> T) throws -> T {
        do { try live(); return try work() }
        catch { invalid = true; channel.invalidateSetup("Operation display proof invalid"); throw error }
    }
    private func save<T: Encodable>(_ value: T, name: String) throws -> Data {
        let raw = try ProbePhysicalOperationChannel.encode(value), path = channel.url(name)
        guard !FileManager.default.fileExists(atPath: path.path) else { throw Failure.publication }
        try raw.write(to: path, options: .atomic)
        guard try channel.readArtifact(name, limit: 1_048_576) == raw else { throw Failure.publication }
        publishedArtifacts[name] = ProbePhysicalInputExchange.sha(raw)
        return raw
    }
    private func payload(_ scene: String, phase: String) throws -> String {
        guard let digest = digests[scene] else { throw Failure.identity }
        return ["DDH06", "1", channel.identity.runID, nonce, scene, digest, phase].joined(separator: "|")
    }
    static func image(_ payload: String) throws -> UIImage {
        guard payload.utf8.count <= 512, let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Failure.surface }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage"); filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: .init(scaleX: 4, y: 4)),
                                                  from: output.extent.applying(.init(scaleX: 4, y: 4))) else {
            throw Failure.surface
        }
        return UIImage(cgImage: image, scale: 4, orientation: .up)
    }
    private func binding(_ row: ProbePhysicalInputWindow) -> Binding {
        .init(logicalSceneID: row.logicalSceneID, nativeSceneID: row.nativeSceneID, generation: row.generation,
              windowIdentity: row.windowIdentity, rootIdentity: row.rootIdentity)
    }
    private func window(_ binding: Binding) throws -> UIWindow {
        guard let handle = registry.handle(logicalSceneID: binding.logicalSceneID),
              handle.nativeSceneID == binding.nativeSceneID, handle.disconnectGeneration == binding.generation,
              let window = registry.window(for: handle), let scene = window.windowScene,
              let root = window.rootViewController, scene.session.persistentIdentifier == binding.nativeSceneID,
              Self.identity(window) == binding.windowIdentity, Self.identity(root) == binding.rootIdentity,
              root.viewIfLoaded?.window === window else { throw Failure.ownership }
        return window
    }
    func begin() throws {
        try terminal {
            guard current == nil, surfaces.isEmpty else { throw Failure.sequence }
            let value = snapshot()
            guard value.failure == nil, value.input.map(\.logicalSceneID) == ["scene-A", "scene-B"] else { throw Failure.ownership }
            for row in value.input {
                let bound = binding(row), raw = try save(binding(row), name: "display-binding-" + row.logicalSceneID + ".json")
                digests[row.logicalSceneID] = ProbePhysicalInputExchange.sha(raw)
                let owned = try window(bound)
                let surface = Surface(window: owned, binding: bound,
                    ownerImage: try Self.image(payload(row.logicalSceneID, phase: "OWNER")),
                    phaseImage: try Self.image(payload(row.logicalSceneID, phase: Phase.start.rawValue)))
                surfaces[row.logicalSceneID] = surface
                try surface.layout()
            }
            guard Set(surfaces.values.map { $0.binding.windowIdentity }).count == 2,
                  Set(surfaces.values.map { $0.binding.nativeSceneID }).count == 2,
                  Set(surfaces.values.map { $0.binding.rootIdentity }).count == 2 else { throw Failure.ownership }
            try publish(.start, cause: nil)
            proofChain = ProofChain(identity: channel.identity, nonce: nonce, deadlineBits: deadlineBits,
                owners: digests, sourceSHA256: decoderSourceSHA256, binarySHA256: decoderBinarySHA256)
        }
    }
    func validate() throws {
        try terminal {
            guard surfaces.count == 2 else { throw Failure.ownership }
            let value = snapshot()
            guard value.failure == nil else { throw Failure.ownership }
            if current != nil && current != .start {
                guard value.idleFailure() == nil else { throw Failure.ownership }
            }
            for row in value.input {
                guard let surface = surfaces[row.logicalSceneID], binding(row) == surface.binding else { throw Failure.ownership }
                let owned = try window(surface.binding)
                try surface.validate(in: owned)
            }
            guard value.input.map(\.logicalSceneID) == ["scene-A", "scene-B"] else { throw Failure.ownership }
        }
    }
    private func publish(_ phase: Phase, cause: String?) throws {
        for (scene, surface) in surfaces {
            let next = try Self.image(payload(scene, phase: phase.rawValue))
            surface.phaseImage = next; surface.phase.image = next
            try surface.layout()
            if phase == .run { try surface.freezeGeometry() }
        }
        current = phase
        try validate()
        let receipt = Receipt(schemaVersion: 1, identity: channel.identity, nonce: nonce, phase: phase,
            sequence: phase == .start ? 0 : phase == .run ? 1 : 2, deadlineBits: deadlineBits,
            bindings: surfaces.mapValues(\.binding), bindingSHA256: digests,
            surfaces: surfaces.mapValues { $0.geometry() },
            geometryScope: "Phase publication only; START arrangement may change. Host must join fresh native capture and actual pixels.",
            previousReceiptSHA256: latestReceipt.map(ProbePhysicalInputExchange.sha),
            causeSHA256: cause, nativeAcceptance: false)
        latestReceipt = try save(receipt, name: "display-" + phase.rawValue + ".json")
    }
    /// Pure receipt validation is separate from UIKit ownership and visibility.
    @MainActor struct ProofChain {
        let identity: ProbePhysicalOperationChannelIdentity
        let nonce: String
        let deadlineBits: String
        let owners: [String: String]
        let sourceSHA256: String
        let binarySHA256: String
        private var consumed = Set<String>()
        private var anchorReferences: [String: Reference] = [:]
        private var nextPhase = 0
        private(set) var invalid = false

        init(identity: ProbePhysicalOperationChannelIdentity, nonce: String, deadlineBits: String,
             owners: [String: String], sourceSHA256: String, binarySHA256: String) {
            self.identity = identity; self.nonce = nonce; self.deadlineBits = deadlineBits; self.owners = owners
            self.sourceSHA256 = sourceSHA256; self.binarySHA256 = binarySHA256
        }
        mutating func consume(_ raw: Data, phase: Phase, nativeReceiptSHA256: String) throws -> Proof {
            do {
                guard !invalid, raw.count <= 1_048_576, nextPhase < 3,
                      [Phase.start, .run, .final][nextPhase] == phase,
                      ProbePhysicalOperationDisplay.digest(nativeReceiptSHA256) else { throw Failure.proof }
                return try validate(raw, phase: phase, nativeReceiptSHA256: nativeReceiptSHA256)
            } catch { invalid = true; throw error }
        }
        private mutating func validate(_ raw: Data, phase: Phase, nativeReceiptSHA256: String) throws -> Proof {
            let value = try JSONDecoder().decode(Proof.self, from: raw)
            guard try ProbePhysicalOperationChannel.encode(value) == raw,
                  value.schemaVersion == 1, value.identity == identity, value.nonce == nonce,
                  value.phase == phase, value.deadlineBits == deadlineBits, value.owners == owners,
                  value.nativeReceiptSHA256 == nativeReceiptSHA256,
                  UUID(uuidString: value.requestID)?.uuidString.lowercased() == value.requestID, consumed.insert(value.requestID).inserted else { throw Failure.proof }
            let expected = phase == .start ? ["START"] : phase == .run ? ["START", "RUN"] : ["START", "RUN", "FINAL"]
            guard Set(value.anchors.keys) == Set(expected) else { throw Failure.proof }
            for name in expected {
                guard let media = value.anchors[name] else { throw Failure.proof }
                _ = try media.validate(kind: "IMAGE", sourceSHA256: sourceSHA256, binarySHA256: binarySHA256)
                if let previous = anchorReferences[name] { guard previous == media.reference else { throw Failure.proof } }
                else { anchorReferences[name] = media.reference }
            }
            guard Set(value.anchors.values.map(\.reference.sha256)).count == expected.count else { throw Failure.proof }
            if phase == .final {
                guard let movie = value.movie, let assessment = value.assessment else { throw Failure.proof }
                _ = try movie.validate(kind: "MOVIE", sourceSHA256: sourceSHA256, binarySHA256: binarySHA256)
                let decodedMovie = try movie.decoder.decoded(DecoderReceipt.self)
                let summary = try assessment.decoded(PixelAssessment.self)
                guard summary.state == "PIXEL_INTERVAL_CHECKED", !summary.nativeAcceptance, summary.gatesClosed.isEmpty,
                      summary.movie == movie.reference, summary.screenshots == value.anchors.mapValues(\.reference),
                      summary.binding.runID == identity.runID, summary.binding.nonce == nonce,
                      summary.binding.owners == owners, summary.startFrame >= 0, summary.runFrame > summary.startFrame,
                      summary.finalFrame > summary.runFrame, summary.finalFrame < decodedMovie.frameCount,
                      summary.intervalFrames == summary.finalFrame - summary.startFrame + 1,
                      summary.retainedTailFrames == decodedMovie.frameCount - summary.finalFrame - 1,
                      summary.tailScope == ProbePhysicalOperationDisplay.tailScope else { throw Failure.proof }
            } else { guard value.movie == nil, value.assessment == nil else { throw Failure.proof } }
            nextPhase += 1
            return value
        }
    }
    private func proof(_ raw: Data, phase: Phase) throws -> Proof {
        guard let latestReceipt, var chain = proofChain else { throw Failure.proof }
        defer { proofChain = chain }
        return try chain.consume(raw, phase: phase, nativeReceiptSHA256: ProbePhysicalInputExchange.sha(latestReceipt))
    }
    private struct PixelAssessment: Decodable {
        struct Identity: Decodable {
            let runID: String; let nonce: String; let owners: [String: String]
            enum CodingKeys: String, CodingKey { case runID = "run_id", nonce, owners }
        }
        let state: String; let nativeAcceptance: Bool; let gatesClosed: [String]
        let movie: Reference; let screenshots: [String: Reference]; let binding: Identity
        let startFrame: Int; let runFrame: Int; let finalFrame: Int; let intervalFrames: Int; let tailScope: String
        let retainedTailFrames: Int
        enum CodingKeys: String, CodingKey {
            case state, movie, screenshots, binding
            case nativeAcceptance = "native_acceptance", gatesClosed = "gates_closed"
            case startFrame = "start_frame", runFrame = "run_frame", finalFrame = "final_frame"
            case intervalFrames = "interval_frames", tailScope = "tail_scope", retainedTailFrames = "retained_tail_frames"
        }
    }
    private static let tailScope = "All samples after the first complete FINAL are retained but excluded. Native causality must prove no critical work occurs there."
    private func published(_ marker: String) throws -> Data? {
        guard let selection = try channel.readArtifact(marker, limit: 64) else { return nil }
        guard let digest = String(data: selection, encoding: .utf8), Self.digest(digest),
              let raw = try channel.readArtifact(marker + "-" + digest + ".json", limit: 1_048_576),
              ProbePhysicalInputExchange.sha(raw) == digest else { throw Failure.publication }
        return raw
    }
    func pollRunRequest() throws {
        try terminal {
            guard current == .start || current == .run else { throw Failure.sequence }
            if current == .run {
                guard let raw = try published("display-run-request"),
                      ProbePhysicalInputExchange.sha(raw) == runRequestSHA256 else { throw Failure.sequence }
                try validate(); return
            }
            guard let raw = try published("display-run-request") else { return }
            _ = try proof(raw, phase: .start)
            guard snapshot().idleFailure() == nil else { throw Failure.ownership }
            try validate()
            _ = try save(try JSONDecoder().decode(Proof.self, from: raw), name: "display-start-proof-consumed.json")
            runRequestSHA256 = ProbePhysicalInputExchange.sha(raw)
            try publish(.run, cause: runRequestSHA256)
        }
    }
    func consumeRun(_ raw: Data) throws {
        try terminal {
            guard current == .run, runProofSHA256 == nil else { throw Failure.sequence }
            let value = try proof(raw, phase: .run); try validate()
            _ = try save(value, name: "display-run-proof-consumed.json")
            runProofSHA256 = ProbePhysicalInputExchange.sha(raw)
        }
    }
    func seal(_ finalObservationSHA256: String) throws {
        try terminal {
            guard current == .run, runProofSHA256 != nil, Self.digest(finalObservationSHA256) else { throw Failure.sequence }
            try validate(); try publish(.final, cause: finalObservationSHA256)
            sealedObservationSHA256 = finalObservationSHA256
        }
    }
    func pollFinalProof() throws -> Bool {
        try terminal {
            guard current == .final, finalProofSHA256 == nil else { throw Failure.sequence }
            try validate()
            guard let raw = try published("display-final-proof") else { return false }
            let value = try proof(raw, phase: .final)
            _ = try save(value, name: "display-final-proof-consumed.json")
            finalProofSHA256 = ProbePhysicalInputExchange.sha(raw)
            return true
        }
    }
    func finish(context: ProbePhysicalOperationContextSample, observationSHA256: String) throws -> [String: String] {
        try terminal {
            guard current == .final, let finalProofSHA256, let runProofSHA256,
                  observationSHA256 == sealedObservationSHA256, context.failure == nil else {
                throw Failure.sequence
            }
            try validate()
            let raw = try save(context, name: "display-final-context.json")
            _ = try save(["state": "DISPLAY_PROOFS_CONSUMED", "nonce": nonce,
                          "runProofSHA256": runProofSHA256, "finalProofSHA256": finalProofSHA256,
                          "finalObservationSHA256": observationSHA256,
                          "contextSHA256": ProbePhysicalInputExchange.sha(raw)],
                         name: "display-completion.json")
            return publishedArtifacts
        }
    }
    func retire() {
        invalid = true
        channel.invalidateSetup("Operation display retired for cleanup")
        surfaces.values.forEach { $0.view.removeFromSuperview() }
    }
}
