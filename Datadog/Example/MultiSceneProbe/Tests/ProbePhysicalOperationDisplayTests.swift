/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit

@MainActor
final class ProbePhysicalOperationDisplayTests: XCTestCase {
    private typealias Display = ProbePhysicalOperationDisplay
    private let runID = "00000000-0000-0000-0000-000000000010"
    private let nonce = "00000000-0000-0000-0000-000000000011"
    private let source = String(repeating: "a", count: 64)
    private let binary = String(repeating: "b", count: 64)
    private let receipt = String(repeating: "c", count: 64)
    private var owners: [String: String] {
        ["scene-A": String(repeating: "d", count: 64), "scene-B": String(repeating: "e", count: 64)]
    }
    private var identity: ProbePhysicalOperationChannelIdentity {
        .init(schemaVersion: 2, runID: runID, processID: 123,
              profile: .init(sourceRevision: String(repeating: "1", count: 40), buildConfiguration: "Debug",
                             scenarioSHA256: source, inference: ProbePhysicalOperationProfile.inferenceMechanism),
              challengeID: "00000000-0000-0000-0000-000000000012",
              installedCodeSHA256: binary, executionArmed: false)
    }
    private func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: ProbePhysicalOperationChannel.encode(value))
    }
    private func blob(_ value: [String: Any]) throws -> Display.Blob {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return .init(bytes: data, sha256: ProbePhysicalInputExchange.sha(data))
    }
    private func ref(_ path: String, _ hash: String) -> [String: String] { ["path": path, "sha256": hash] }

    // These are synthetic protocol receipts, never a native visibility claim.
    private func media(_ name: String, kind: String = "IMAGE",
                       decoderChange: (inout [String: Any]) -> Void = { _ in },
                       manifestChange: (inout [String: Any]) -> Void = { _ in },
                       invocationChange: (inout [String: Any]) -> Void = { _ in },
                       processChange: (inout [String: Any]) -> Void = { _ in }) throws -> Display.Media {
        let folder = "/evidence/" + name
        let raw = ref(folder + "/capture.bin", String(repeating: "f", count: 64))
        let executable = ref("/decoder/operation-display", binary), decoderSource = ref("/source/operation_display.swift", source)
        var decoded: [String: Any] = ["schemaVersion": 1, "state": "DECODED", "kind": kind,
            "readerState": "completed", "nativeAcceptance": false, "revision": 3,
            "inputSHA256": raw["sha256"]!, "framesSHA256": source, "frameCount": kind == "MOVIE" ? 10 : 1]
        if kind == "MOVIE" {
            decoded["trackCount"] = 1; decoded["decodedOutput"] = true; decoded["pixelFormat"] = 1_111_970_369
        }
        decoderChange(&decoded)
        let decoder = try blob(decoded)
        var command: [String: Any] = ["argv": [executable["path"]!, kind.lowercased(), raw["path"]!, folder + "/decoded"],
            "binary": executable, "decoder_source": decoderSource, "raw": raw, "native_acceptance": false]
        invocationChange(&command)
        let invocation = try blob(command)
        var result: [String: Any] = ["returncode": 0, "timed_out": false]
        processChange(&result)
        let process = try blob(result)
        var inventory: [String: Any] = ["schema_version": 1, "kind": kind, "native_acceptance": false,
            "decoder_source": decoderSource, "executable": executable, "raw": raw,
            "invocation": ref(folder + "/invocation.json", invocation.sha256),
            "process": ref(folder + "/process.json", process.sha256),
            "decoder": ref(folder + "/decoded/decoder.json", decoder.sha256),
            "frames": ref(folder + "/decoded/frames.jsonl", source)]
        manifestChange(&inventory)
        let manifest = try blob(inventory)
        return .init(reference: .init(path: folder + "/manifest.json", sha256: manifest.sha256),
                     manifest: manifest, decoder: decoder, invocation: invocation, process: process)
    }

    private func chain() -> Display.ProofChain {
        .init(identity: identity, nonce: nonce, deadlineBits: String(200.125.bitPattern, radix: 16),
              owners: owners, sourceSHA256: source, binarySHA256: binary)
    }
    private func proof(_ phase: Display.Phase, requestID: String = UUID().uuidString.lowercased(),
                       anchors replacement: [String: Display.Media]? = nil,
                       assessmentChange: (inout [String: Any]) -> Void = { _ in }) throws -> Display.Proof {
        let phases = phase == .start ? ["START"] : phase == .run ? ["START", "RUN"] : ["START", "RUN", "FINAL"]
        let anchors = try replacement ?? Dictionary(uniqueKeysWithValues: phases.map { ($0, try media($0)) })
        let movie = phase == .final ? try media("movie", kind: "MOVIE") : nil
        var assessment: Display.Blob?
        if let movie {
            var value: [String: Any] = ["state": "PIXEL_INTERVAL_CHECKED", "native_acceptance": false, "gates_closed": [],
                "movie": try object(movie.reference), "screenshots": try object(anchors.mapValues(\.reference)),
                "binding": ["run_id": runID, "nonce": nonce, "owners": owners],
                "start_frame": 0, "run_frame": 3, "final_frame": 7, "interval_frames": 8, "retained_tail_frames": 2,
                "tail_scope": "All samples after the first complete FINAL are retained but excluded. Native causality must prove no critical work occurs there."]
            assessmentChange(&value); assessment = try blob(value)
        }
        return .init(schemaVersion: 1, identity: identity, nonce: nonce, phase: phase, requestID: requestID,
                     nativeReceiptSHA256: receipt, deadlineBits: String(200.125.bitPattern, radix: 16),
                     owners: owners, anchors: anchors, movie: movie, assessment: assessment)
    }
    private func consume(_ proof: Display.Proof, _ chain: inout Display.ProofChain) throws {
        _ = try chain.consume(ProbePhysicalOperationChannel.encode(proof), phase: proof.phase, nativeReceiptSHA256: receipt)
    }

    func testCompleteDistinctPhaseProofsBindOriginalArtifacts() throws {
        var state = chain()
        for phase in [Display.Phase.start, .run, .final] { try consume(proof(phase), &state) }
        XCTAssertFalse(state.invalid)
        XCTAssertThrowsError(try consume(proof(.final), &state))
        XCTAssertTrue(state.invalid)
    }

    func testPhaseOrderAndReusedRequestPermanentlyInvalidate() throws {
        for phase in [Display.Phase.run, .final] {
            var state = chain()
            XCTAssertThrowsError(try consume(proof(phase), &state))
            XCTAssertThrowsError(try consume(proof(.start), &state))
        }
        var state = chain()
        let start = try proof(.start)
        try consume(start, &state)
        XCTAssertThrowsError(try consume(proof(.run, requestID: start.requestID), &state))
        XCTAssertThrowsError(try consume(proof(.run), &state))
    }

    func testForeignBindingAndNoncanonicalEnvelopeCannotRecover() throws {
        let original = try ProbePhysicalOperationChannel.encode(proof(.start))
        for field in ["nonce", "owners", "nativeReceiptSHA256", "deadlineBits", "identity", "unknown"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            if field == "owners" || field == "identity" { value[field] = [:] }
            else { value[field] = "foreign" }
            let changed = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            var state = chain()
            XCTAssertThrowsError(try state.consume(changed, phase: .start, nativeReceiptSHA256: receipt), field)
            XCTAssertTrue(state.invalid)
            XCTAssertThrowsError(try state.consume(original, phase: .start, nativeReceiptSHA256: receipt), field)
        }
    }

    func testMissingAliasedAndReplacedAnchorRejectsBeforeRun() throws {
        for mode in ["missing", "alias", "replacement"] {
            var state = chain()
            let start = try proof(.start)
            try consume(start, &state)
            var anchors = ["START": try media("START"), "RUN": try media("RUN")]
            if mode == "missing" { anchors.removeValue(forKey: "START") }
            if mode == "alias" { anchors["RUN"] = anchors["START"] }
            if mode == "replacement" { anchors["START"] = try media("new-start") }
            XCTAssertThrowsError(try consume(proof(.run, anchors: anchors), &state), mode)
            XCTAssertTrue(state.invalid)
        }
    }

    func testIncompleteOrContradictoryDecoderAndProcessReceiptsFail() throws {
        let changes: [(String, Any)] = [("state", "PARTIAL"), ("revision", 2), ("readerState", "reading"),
            ("nativeAcceptance", true), ("frameCount", 0), ("frameCount", 2),
            ("inputSHA256", binary), ("framesSHA256", binary)]
        for (key, value) in changes {
            let changed = try media("START", decoderChange: { $0[key] = value })
            XCTAssertThrowsError(try changed.validate(kind: "IMAGE", sourceSHA256: source, binarySHA256: binary), key)
        }
        for key in ["returncode", "timed_out"] {
            let changed = try media("START", processChange: { $0[key] = key == "returncode" ? 1 : true })
            XCTAssertThrowsError(try changed.validate(kind: "IMAGE", sourceSHA256: source, binarySHA256: binary), key)
        }
        for key in ["trackCount", "decodedOutput", "pixelFormat"] {
            let changed = try media("movie", kind: "MOVIE", decoderChange: { $0[key] = 0 })
            XCTAssertThrowsError(try changed.validate(kind: "MOVIE", sourceSHA256: source, binarySHA256: binary), key)
        }
    }

    func testArtifactSubstitutionAndInvocationDriftReject() throws {
        for key in ["decoder", "process", "invocation", "executable", "decoder_source", "frames", "raw"] {
            let changed = try media("START", manifestChange: { $0[key] = self.ref("/foreign", self.receipt) })
            XCTAssertThrowsError(try changed.validate(kind: "IMAGE", sourceSHA256: source, binarySHA256: binary), key)
        }
        let changed = try media("START", invocationChange: { $0["argv"] = ["/foreign"] })
        XCTAssertThrowsError(try changed.validate(kind: "IMAGE", sourceSHA256: source, binarySHA256: binary))
        let good = try media("START")
        let altered = Display.Media(reference: good.reference, manifest: good.manifest,
            decoder: .init(bytes: Data("changed".utf8), sha256: good.decoder.sha256),
            invocation: good.invocation, process: good.process)
        XCTAssertThrowsError(try altered.validate(kind: "IMAGE", sourceSHA256: source, binarySHA256: binary))
    }

    func testFinalAssessmentMustJoinCompleteMovieAndExactAnchorSet() throws {
        for field in ["movie", "screenshots", "binding", "final_frame", "overflow", "retained_tail_frames", "gates_closed", "tail_scope"] {
            var state = chain()
            try consume(proof(.start), &state); try consume(proof(.run), &state)
            let final = try proof(.final, assessmentChange: {
                switch field {
                case "final_frame": $0[field] = 10; $0["interval_frames"] = 11
                case "overflow": $0["final_frame"] = Int.max; $0["interval_frames"] = Int.max
                case "retained_tail_frames": $0[field] = 0
                case "gates_closed": $0[field] = ["S3:H06"]
                case "tail_scope": $0[field] = "accepted tail"
                default: $0[field] = [:]
                }
            })
            XCTAssertThrowsError(try consume(final, &state), field)
            XCTAssertTrue(state.invalid)
        }
    }

    private func surface() throws -> (UIWindow, Display.Surface) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIViewController()
        let binding = Display.Binding(logicalSceneID: "scene-A", nativeSceneID: "native-A", generation: 0,
                                      windowIdentity: "test-window", rootIdentity: "test-root")
        let surface = Display.Surface(window: window, binding: binding,
            ownerImage: try Display.image("DDH06|OWNER"), phaseImage: try Display.image("DDH06|START"))
        try surface.layout()
        return (window, surface)
    }

    func testPassiveSurfaceKeepsRootAndKeyOwnershipAndSnapsToPixels() throws {
        let (window, surface) = try surface()
        let root = window.rootViewController, key = window.isKeyWindow
        try surface.validate(in: window)
        XCTAssertFalse(surface.view.isUserInteractionEnabled)
        XCTAssertTrue(surface.view.gestureRecognizers?.isEmpty ?? true)
        XCTAssertTrue(window.rootViewController === root); XCTAssertEqual(window.isKeyWindow, key)
        let scale = surface.view.traitCollection.displayScale
        for view in [surface.owner, surface.phase] {
            for value in [view.frame.minX, view.frame.minY, view.frame.width, view.frame.height] {
                XCTAssertEqual(value * scale, (value * scale).rounded(), accuracy: 0.000_001)
            }
        }
        try surface.freezeGeometry()
        surface.owner.frame.origin.x += 0.000_000_001
        XCTAssertNoThrow(try surface.validate(in: window))
        surface.owner.frame.origin.x += 2 / scale
        XCTAssertThrowsError(try surface.validate(in: window))
    }

    func testDetachedHiddenReplacedOrTransformedSurfaceRejects() throws {
        for change in ["detach", "hidden", "alpha", "root", "image", "transform", "resize"] {
            let (window, surface) = try surface()
            try surface.freezeGeometry()
            switch change {
            case "detach": surface.view.removeFromSuperview()
            case "hidden": surface.owner.isHidden = true
            case "alpha": surface.view.alpha = 0.5
            case "root": window.rootViewController = UIViewController()
            case "image": surface.phase.image = try Display.image("foreign")
            case "transform": surface.view.transform = CGAffineTransform(translationX: 5, y: 0)
            case "resize": surface.view.frame.size.width = 380; try? surface.layout()
            default: XCTFail("unknown mutation")
            }
            XCTAssertThrowsError(try surface.validate(in: window), change)
        }
    }

    func testFullMarkerPayloadRenderingExportsActualSurfacePixels() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800), format: format)
        for phase in ["START", "RUN", "FINAL"] {
            var windows: [UIWindow] = [], surfaces: [Display.Surface] = []
            for scene in ["scene-A", "scene-B"] {
                let (window, surface) = try surface()
                let prefix = ["DDH06", "1", runID, nonce, scene, owners[scene]!].joined(separator: "|")
                surface.ownerImage = try Display.image(prefix + "|OWNER"); surface.owner.image = surface.ownerImage
                surface.phaseImage = try Display.image(prefix + "|" + phase); surface.phase.image = surface.phaseImage
                try surface.layout(); try surface.validate(in: window)
                windows.append(window); surfaces.append(surface)
            }
            let image = renderer.image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
                for (index, surface) in surfaces.enumerated() {
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: CGFloat(index) * 400, y: 0)
                    surface.view.layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                }
            }
            XCTAssertEqual(windows.count, 2)
            let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
            attachment.name = "operation-display-" + phase + ".png"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testStartArrangementMayResizeBeforeRunGeometryIsFrozen() throws {
        let (window, surface) = try surface()
        surface.view.frame.size.width = 380
        try surface.layout(); try surface.validate(in: window)
        try surface.freezeGeometry()
        surface.view.frame.size.width = 390
        XCTAssertThrowsError(try surface.layout())
    }
}
