// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation
import Darwin

@main
struct BackgroundSessionChecks {
    typealias C = ProbeSceneBackgroundControl
    typealias P = ProbeSceneBackgroundPhase
    typealias S = ProbeSceneBackgroundCapture
    enum Invalid: Error { case assertion, native }
    struct Result: Encodable { let name: String; let passed: Bool; let sealed: Bool; let detail: String }

    @MainActor
    final class Fixture {
        let root: URL
        let mode: String
        var now: Int64 = 1_000
        var stopped = false
        var current: S.Snapshot
        var control: C!
        var phase: P!
        var capture: S!
        var seq = 1
        var previous = ""
        var inspected: String?
        var observation: Data?
        var pendingDigest = ""
        var nativeChecks = 0
        let actualNative: Data
        let oracle: String

        init(root: URL, mode: String, initial: S.Snapshot, oracle: String, witness: Data) throws {
            self.root = root; self.mode = mode; current = initial; self.oracle = oracle; actualNative = witness
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let identity = C.Identity(schemaVersion: 1, runID: "synthetic-h10-only", processID: 123,
                scenarioID: C.scenarioID, profile: C.profile, sourceRevision: String(repeating: "a", count: 40),
                installedCodeSHA256: String(repeating: "b", count: 64), challengeID: UUID().uuidString.lowercased(),
                executionDeadlineMilliseconds: 100_000, cleanupDeadlineMilliseconds: 200_000)
            control = try C(directory: root.appendingPathComponent("channel"), identity: identity, now: now,
                observe: { _ in .init(before: Data("before".utf8), after: Data("after".utf8), idle: true, reason: nil) },
                stop: { [unowned self] in stopped = true },
                driver: { [unowned self] in .init(requested: stopped, stopped: stopped, terminal: nil) })
            capture = try S(directory: control.directory.appendingPathComponent("evidence"), identity: identity,
                oracleSourceSHA256: oracle, snapshot: { [unowned self] in current },
                witness: { [unowned self] in actualNative })
            phase = P(control: control, clock: { [unowned self] in now }, observe: { [unowned self] in
                try capture.inspect(boundary: phase.challenge?.name ?? "unknown")
            }, seal: { [unowned self] inspected, proof, display in
                let result = try capture.seal(inspected: inspected, proof: proof, display: display, challenge: phase.challenge!) { raw in
                    guard raw == self.actualNative else { throw Invalid.assertion }
                    self.nativeChecks += 1
                    if self.mode == "native-before" || (self.mode == "native-after" && self.nativeChecks == 2) { throw Invalid.native }
                }
                if mode == "cutoff-after-seal" { now = control.identity.executionDeadlineMilliseconds }
                if mode == "reply-collision" { try Data("collision".utf8).write(to: folder.appendingPathComponent(pendingDigest + ".reply.json")) }
                return result
            })
        }
        var folder: URL { control.directory.appendingPathComponent(phase.challenge?.consumedPhaseReplies == nil
            ? "phase-\(phase.challenge?.phase ?? -1)" : "collection") }
        func resetChain() throws {
            seq = 1; inspected = nil; observation = nil
            previous = C.sha(try Data(contentsOf: folder.appendingPathComponent("challenge.json")))
        }
        func base(_ operation: String) throws {
            let raw = try C.encode(C.Request(identity: control.identity, commandID: UUID().uuidString.lowercased(), operation: operation))
            let hash = C.sha(raw)
            try raw.write(to: control.directory.appendingPathComponent(hash + ".json"), options: .withoutOverwriting)
            try Data(hash.utf8).write(to: control.directory.appendingPathComponent(operation + ".request"), options: .atomic)
        }
        @discardableResult
        func command(_ operation: String, proof: Data? = nil) throws -> P.Reply? {
            var request = P.Request(challenge: phase.challenge!, sequence: seq, commandID: UUID().uuidString.lowercased(),
                operation: operation, previousReplySHA256: previous,
                inspectedReplySHA256: operation == "inspect" ? nil : inspected,
                displayReceiptSHA256: operation == "inspect" ? nil : String(repeating: "d", count: 64))
            request.semanticProof = proof
            let raw = try C.encode(request), hash = C.sha(raw); pendingDigest = hash
            try raw.write(to: folder.appendingPathComponent(hash + ".json"), options: .withoutOverwriting)
            try Data(hash.utf8).write(to: folder.appendingPathComponent("command.request"), options: .atomic)
            try phase.poll()
            let url = folder.appendingPathComponent(hash + ".reply.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let response = try Data(contentsOf: url), reply = try JSONDecoder().decode(P.Reply.self, from: response)
            guard reply.requestSHA256 == hash, reply.challenge == request.challenge,
                  reply.commandID == request.commandID, reply.sequence == seq, reply.operation == operation else { throw Invalid.assertion }
            previous = C.sha(response); seq += 1
            if operation == "inspect" {
                guard reply.observationSHA256 == reply.observation.map(C.sha) else { throw Invalid.assertion }
                inspected = previous; observation = reply.observation
            }
            return reply
        }
        func start(finalSequence: UInt64) throws {
            try base("arm"); try phase.poll()
            for index in 0..<3 {
                try phase.begin(index); try resetChain(); try command("inspect"); try command("permit")
                if mode == "premature-collection" && index == 2 { try phase.beginCollection(finalInvocationSequence: finalSequence) }
                try phase.consume(index)
            }
            try phase.beginCollection(finalInvocationSequence: mode == "zero-invocation" ? 0 : finalSequence)
            try resetChain()
        }
    }

    @MainActor
    static func exercise(_ item: [String: Any], root: URL, oracle: String) throws -> Result {
        let name = item["name"] as! String, mode = item["mode"] as! String, accept = item["accept"] as! Bool
        func snapshot(_ key: String, terminal: Bool) throws -> S.Snapshot {
            let rows = item[key] as! [[String: Any]]
            return try .init(signals: rows.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) },
                terminal: terminal ? Data("{\"state\":\"PASS\"}".utf8) : nil)
        }
        let initial = try snapshot("initial", terminal: mode == "terminal-before")
        let native = try JSONSerialization.data(withJSONObject: item["witness"]!, options: [.sortedKeys, .withoutEscapingSlashes])
        let fixture = try Fixture(root: root.appendingPathComponent(name), mode: mode, initial: initial, oracle: oracle, witness: native)
        var accepted = false
        var detail = ""
        do {
            let finalSequence = try fixture.capture.rows(initial).first { $0.name == "h10.invoke.B.after-A-foreground" }!.sequence
            try fixture.start(finalSequence: finalSequence)
            if mode != "missing-inspection" { try fixture.command("inspect") }
            let reference = fixture.observation.flatMap { try? JSONDecoder().decode(S.Reference.self, from: $0) }
            let local = try JSONSerialization.data(withJSONObject: item["result"]!, options: [.sortedKeys, .withoutEscapingSlashes])
            let proof = S.HostProof(identity: fixture.control.identity,
                captureSHA256: mode == "wrong-capture" ? String(repeating: "e", count: 64) : (reference?.sha256 ?? String(repeating: "f", count: 64)),
                oracleSourceSHA256: mode == "wrong-oracle" ? String(repeating: "e", count: 64) : oracle,
                displayReceiptSHA256: String(repeating: mode == "wrong-display" ? "e" : "d", count: 64),
                consumedPhaseReplies: mode == "wrong-consumed" ? [] : fixture.phase.challenge!.consumedPhaseReplies!,
                finalInvocationSequence: mode == "wrong-invocation" ? 1 : finalSequence, localResult: local)
            fixture.current = try snapshot("fresh", terminal: mode == "terminal-after")
            if mode == "stop" { try fixture.base("stop") }
            if mode == "cutoff" { fixture.now = fixture.control.identity.executionDeadlineMilliseconds }
            if mode == "unknown-command" { try Data("staged".utf8).write(to: fixture.folder.appendingPathComponent("unknown.json")) }
            if mode == "mutated-phase" {
                try Data("changed".utf8).write(to: fixture.control.directory.appendingPathComponent("phase-0/consumed.json"))
            }
            if mode == "changed-capture", let reference {
                try Data("changed".utf8).write(to: fixture.control.directory.appendingPathComponent("evidence/"+reference.name))
            }
            if mode == "symlink-capture", let reference {
                let file = fixture.control.directory.appendingPathComponent("evidence/"+reference.name)
                let retained = fixture.root.appendingPathComponent("retained-capture.json")
                try FileManager.default.moveItem(at: file, to: retained)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: retained)
            }
            let response = try fixture.command("seal", proof: C.encode(proof))
            accepted = response?.outcome == "sealed" && fixture.phase.state == .sealed && fixture.capture.sealed
            if accepted {
                guard response?.seal != nil, fixture.nativeChecks == 2 else { throw Invalid.assertion }
                if mode == "duplicate-seal" {
                    var rejected = false
                    do { _ = try fixture.command("seal", proof: C.encode(proof)) } catch { rejected = true }
                    guard rejected, fixture.phase.state == .stopped, fixture.stopped else { throw Invalid.assertion }
                }
                if mode == "cleanup-tail" {
                    let before = fixture.observation!
                    fixture.current = S.Snapshot(signals: fixture.current.signals, terminal: Data("{\"state\":\"PASS\"}".utf8))
                    let tail = try fixture.capture.inspect(boundary: "control-stop")
                    let (_, actual) = try fixture.capture.capture(tail)
                    let (_, old) = try fixture.capture.capture(before)
                    guard actual.snapshot.terminal != nil, old.snapshot.terminal == nil else { throw Invalid.assertion }
                }
            }
        } catch {
            detail = String(describing: error)
            if accept { return Result(name: name, passed: false, sealed: accepted, detail: detail) }
        }
        return Result(name: name, passed: accepted == accept, sealed: accepted, detail: detail)
    }

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { throw Invalid.assertion }
        let input = URL(fileURLWithPath: CommandLine.arguments[1]), root = URL(fileURLWithPath: CommandLine.arguments[2])
        let oracle = CommandLine.arguments[3]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let items = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [[String: Any]]
        let result = try items.map { try exercise($0, root: root, oracle: oracle) }
        try C.encode(result).write(to: root.appendingPathComponent("results.json"), options: .withoutOverwriting)
        print("capture/transport controls: \(result.filter(\.passed).count)/\(result.count)")
        if result.contains(where: { !$0.passed }) { exit(1) }
    }
}
