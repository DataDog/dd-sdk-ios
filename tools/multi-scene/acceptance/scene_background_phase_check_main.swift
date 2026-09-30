// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation
import Darwin

/// Real local files and the actual transport; observations and driver are synthetic.
@main
struct BackgroundPhaseChecks {
    typealias Control = ProbeSceneBackgroundControl
    typealias Phase = ProbeSceneBackgroundPhase
    enum Invalid: Error { case assertion, observation, arguments }
    struct Result: Encodable {
        let name: String
        let passed: Bool
        let observations: Int
        let permitsConsumed: Int
        let stopped: Bool
        let detail: String
    }

    @MainActor
    final class Fixture {
        let directory: URL
        var now: Int64 = 1_000
        var requested = false
        var observations = 0
        var consumed = 0
        var expireDuringObservation = false
        var rejectObservation = false
        let raw = Data("{\"width\":597.3333333333334,\"height\":700.6666666666667,\"observed\":true}\n".utf8)
        var control: Control!
        var phase: Phase!
        var sequence = 1
        var previous = ""
        var inspected: String?

        init(_ directory: URL) throws {
            self.directory = directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let identity = Control.Identity(schemaVersion: 1, runID: "h10-phase-controls", processID: 123,
                scenarioID: Control.scenarioID, profile: Control.profile, sourceRevision: String(repeating: "a", count: 40),
                installedCodeSHA256: String(repeating: "b", count: 64), challengeID: UUID().uuidString.lowercased(),
                executionDeadlineMilliseconds: 100_000, cleanupDeadlineMilliseconds: 200_000)
            control = try Control(directory: directory.appendingPathComponent("control"), identity: identity, now: now,
                observe: { _ in .init(before: Data("before".utf8), after: Data("after".utf8), idle: true, reason: nil) },
                stop: { [unowned self] in requested = true },
                driver: { [unowned self] in .init(requested: requested, stopped: requested, terminal: nil) })
            phase = Phase(control: control, clock: { [unowned self] in now }, observe: { [unowned self] in
                observations += 1
                if rejectObservation { throw Invalid.observation }
                if expireDuringObservation { now = control.identity.executionDeadlineMilliseconds }
                return raw
            })
        }

        func baseCommand(_ operation: String) throws {
            let value = Control.Request(identity: control.identity, commandID: UUID().uuidString.lowercased(), operation: operation)
            let bytes = try Control.encode(value), digest = Control.sha(bytes)
            try bytes.write(to: control.directory.appendingPathComponent(digest + ".json"), options: .withoutOverwriting)
            try Data(digest.utf8).write(to: control.directory.appendingPathComponent(operation + ".request"), options: .atomic)
        }
        func arm() throws {
            try baseCommand("arm"); try phase.poll()
            guard control.phase == .armed else { throw Invalid.assertion }
        }
        var folder: URL { control.directory.appendingPathComponent("phase-\(phase.challenge?.phase ?? -1)") }
        func begin(_ index: Int) throws {
            try phase.begin(index)
            sequence = 1; inspected = nil
            previous = Control.sha(try Data(contentsOf: folder.appendingPathComponent("challenge.json")))
        }
        func request(_ operation: String, challenge: Phase.Challenge? = nil,
                     sequence: Int? = nil, previous: String? = nil, inspected: String? = nil,
                     command: String? = nil) -> Phase.Request {
            .init(challenge: challenge ?? phase.challenge!, sequence: sequence ?? self.sequence,
                  commandID: command ?? UUID().uuidString.lowercased(), operation: operation,
                  previousReplySHA256: previous ?? self.previous,
                  inspectedReplySHA256: operation == "permit" ? (inspected ?? self.inspected) : nil,
                  displayReceiptSHA256: operation == "permit" ? String(repeating: "d", count: 64) : nil)
        }
        @discardableResult
        func publish(_ request: Phase.Request, body: Bool = true, marker: Bool = true) throws -> String {
            let bytes = try Control.encode(request), digest = Control.sha(bytes)
            if body { try bytes.write(to: folder.appendingPathComponent(digest + ".json"), options: .withoutOverwriting) }
            if marker { try Data(digest.utf8).write(to: folder.appendingPathComponent("command.request"), options: .atomic) }
            return digest
        }
        @discardableResult
        func collect(_ request: Phase.Request) throws -> String {
            let digest = Control.sha(try Control.encode(request))
            let bytes = try Data(contentsOf: folder.appendingPathComponent(digest + ".reply.json"))
            let reply = try JSONDecoder().decode(Phase.Reply.self, from: bytes)
            guard reply.requestSHA256 == digest, reply.challenge == request.challenge,
                  reply.sequence == sequence, reply.commandID == request.commandID,
                  reply.operation == request.operation else { throw Invalid.assertion }
            if request.operation == "inspect" {
                guard reply.outcome == "observed", reply.observation == raw,
                      reply.observationSHA256 == Control.sha(raw) else { throw Invalid.assertion }
                inspected = Control.sha(bytes)
            } else {
                guard reply.outcome == "granted", reply.inspectedReplySHA256 == inspected,
                      reply.displayReceiptSHA256 == request.displayReceiptSHA256 else { throw Invalid.assertion }
            }
            previous = Control.sha(bytes); sequence += 1
            return previous
        }
        @discardableResult
        func inspect() throws -> String {
            let request = request("inspect"); try publish(request); try phase.poll()
            return try collect(request)
        }
        func permit() throws {
            let request = request("permit"); try publish(request); try phase.poll(); try collect(request)
        }
        func consume() throws {
            try phase.consume(phase.challenge!.phase)
            guard phase.state == .consumed, FileManager.default.fileExists(atPath: folder.appendingPathComponent("consumed.json").path) else { throw Invalid.assertion }
            consumed += 1
        }
        func rejects(_ work: () throws -> Void) throws {
            var rejected = false
            do { try work() } catch { rejected = true }
            guard rejected else { throw Invalid.assertion }
            do { try phase.consume(phase.challenge?.phase ?? 0); throw Invalid.assertion }
            catch Invalid.assertion { throw Invalid.assertion }
            catch { }
            guard requested, phase.state == .stopped, phase.failure != nil else { throw Invalid.assertion }
        }
    }

    @MainActor
    static func exercise(_ name: String, root: URL) async -> Result {
        var fixture: Fixture?
        do {
            let f = try Fixture(root.appendingPathComponent(name)); fixture = f
            try f.arm(); try f.begin(0)
            switch name {
            case "complete-three-phase-cycle":
                for index in 0..<3 {
                    if index > 0 { try f.begin(index) }
                    try f.inspect(); try f.permit(); try f.consume()
                }
                guard f.observations == 3, f.consumed == 3 else { throw Invalid.assertion }
            case "partial-publication-stays-pending":
                let request = f.request("inspect"), bytes = try Control.encode(request), digest = Control.sha(bytes)
                try Data(digest.prefix(12).utf8).write(to: f.folder.appendingPathComponent("command.request"))
                try f.phase.poll()
                try f.publish(request, body: false); try f.phase.poll()
                try bytes.prefix(16).write(to: f.folder.appendingPathComponent(digest + ".json")); try f.phase.poll()
                guard f.observations == 0, f.phase.state == .waiting else { throw Invalid.assertion }
                try bytes.write(to: f.folder.appendingPathComponent(digest + ".json")); try f.phase.poll()
                try f.collect(request); try f.permit(); try f.consume()
                guard f.observations == 1, f.consumed == 1 else { throw Invalid.assertion }
            case "same-marker-is-idempotent":
                try f.inspect(); try f.phase.poll(); try f.phase.poll()
                guard f.observations == 1 else { throw Invalid.assertion }
                try f.permit(); try f.consume()
            case "permit-without-inspection":
                try f.publish(f.request("permit", inspected: String(repeating: "e", count: 64)))
                try f.rejects { try f.phase.poll() }
            case "old-basis-after-new-inspection", "late-older-reply-chain":
                let old = try f.inspect(); try f.inspect()
                let request = f.request("permit", previous: name == "late-older-reply-chain" ? old : nil, inspected: old)
                try f.publish(request); try f.rejects { try f.phase.poll() }
            case "duplicate-command-id":
                let first = f.request("inspect"); try f.publish(first); try f.phase.poll(); try f.collect(first)
                try f.publish(f.request("inspect", command: first.commandID)); try f.rejects { try f.phase.poll() }
            case "old-sequence-replayed":
                let first = f.request("inspect"); try f.publish(first); try f.phase.poll(); try f.collect(first)
                try f.inspect(); try f.publish(first, body: false); try f.rejects { try f.phase.poll() }
            case "permit-replaces-unknown-publication":
                try f.inspect()
                try f.publish(f.request("inspect"), body: false); try f.phase.poll()
                try f.publish(f.request("permit")); try f.rejects { try f.phase.poll() }
            case "unknown-inspection-body-after-grant":
                try f.inspect(); try f.permit(); try f.publish(f.request("inspect"), marker: false)
                try f.rejects { try f.consume() }
            case "partial-marker-after-grant":
                try f.inspect(); try f.permit()
                try Data("abc".utf8).write(to: f.folder.appendingPathComponent("command.request"))
                try f.rejects { try f.consume() }
            case "duplicate-permit":
                try f.inspect(); try f.permit(); try f.publish(f.request("permit"))
                try f.rejects { try f.phase.poll() }
            case "duplicate-consume":
                try f.inspect(); try f.permit(); try f.consume(); try f.rejects { try f.consume() }
            case "repeated-phase", "future-phase":
                try f.rejects { try f.begin(name == "repeated-phase" ? 0 : 1) }
            case "foreign-phase-challenge", "foreign-run-directory":
                let challenge: Phase.Challenge
                if name == "foreign-run-directory" {
                    let other = try Fixture(root.appendingPathComponent(name + "-other")); try other.arm(); try other.begin(0)
                    challenge = other.phase.challenge!
                } else {
                    let old = f.phase.challenge!
                    challenge = .init(identity: old.identity, phase: 1, name: Phase.names[1],
                                      challengeID: old.challengeID, maximumInspections: old.maximumInspections)
                }
                try f.publish(f.request("inspect", challenge: challenge)); try f.rejects { try f.phase.poll() }
            case "mutated-inspect-request", "mutated-inspect-reply":
                let request = f.request("inspect"); let digest = try f.publish(request)
                try f.phase.poll(); try f.collect(request); try f.permit()
                let suffix = name == "mutated-inspect-request" ? ".json" : ".reply.json"
                try Data("mutated".utf8).write(to: f.folder.appendingPathComponent(digest + suffix))
                try f.rejects { try f.consume() }
            case "reply-collision":
                let digest = try f.publish(f.request("inspect"))
                try Data("occupied".utf8).write(to: f.folder.appendingPathComponent(digest + ".reply.json"))
                try f.rejects { try f.phase.poll() }
            case "observation-failed", "observation-crosses-cutoff":
                f.rejectObservation = name == "observation-failed"
                f.expireDuringObservation = name == "observation-crosses-cutoff"
                try f.publish(f.request("inspect")); try f.rejects { try f.phase.poll() }
            case "stop-precedes-inspection", "stop-precedes-permit":
                let permit = name == "stop-precedes-permit"
                if permit { try f.inspect() }
                let calls = f.observations
                try f.baseCommand("stop"); try f.publish(f.request(permit ? "permit" : "inspect"))
                try f.phase.poll(); try f.rejects { try f.consume() }
                guard f.observations == calls, f.consumed == 0 else { throw Invalid.assertion }
            case "execution-cutoff", "cleanup-cutoff":
                try f.inspect(); try f.permit()
                f.now = name == "execution-cutoff" ? f.control.identity.executionDeadlineMilliseconds : f.control.identity.cleanupDeadlineMilliseconds
                try f.rejects { try f.consume() }
            case "inspection-limit":
                for _ in 0..<Phase.maximumInspections { try f.inspect() }
                try f.publish(f.request("inspect")); try f.rejects { try f.phase.poll() }
                guard f.observations == Phase.maximumInspections else { throw Invalid.assertion }
            case "extra-request-field":
                let request = f.request("inspect")
                var object = try JSONSerialization.jsonObject(with: Control.encode(request)) as! [String: Any]
                object["extra"] = true
                let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                let digest = Control.sha(bytes)
                try bytes.write(to: f.folder.appendingPathComponent(digest + ".json"))
                try Data(digest.utf8).write(to: f.folder.appendingPathComponent("command.request"))
                try f.rejects { try f.phase.poll() }
            case "symlink-request":
                let bytes = try Control.encode(f.request("inspect")), digest = Control.sha(bytes)
                let target = f.directory.appendingPathComponent("redirected.json"); try bytes.write(to: target)
                try FileManager.default.createSymbolicLink(at: f.folder.appendingPathComponent(digest + ".json"), withDestinationURL: target)
                try Data(digest.utf8).write(to: f.folder.appendingPathComponent("command.request"))
                try f.rejects { try f.phase.poll() }
            case "cancel-before-consume":
                try f.inspect(); try f.permit()
                let task = Task { @MainActor in
                    while !Task.isCancelled { await Task.yield() }
                    try f.rejects { try f.consume() }
                }
                task.cancel(); try await task.value
            default: throw Invalid.assertion
            }
            return .init(name: name, passed: true, observations: f.observations, permitsConsumed: f.consumed,
                         stopped: f.requested, detail: "Expected transport outcome; no native or SDK work")
        } catch {
            return .init(name: name, passed: false, observations: fixture?.observations ?? 0,
                         permitsConsumed: fixture?.consumed ?? 0, stopped: fixture?.requested ?? false,
                         detail: String(describing: error))
        }
    }

    @MainActor
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw Invalid.arguments }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            guard !FileManager.default.fileExists(atPath: root.path) else { throw Invalid.arguments }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let names = ["complete-three-phase-cycle", "partial-publication-stays-pending", "same-marker-is-idempotent",
                "permit-without-inspection", "old-basis-after-new-inspection", "late-older-reply-chain", "duplicate-command-id",
                "old-sequence-replayed", "permit-replaces-unknown-publication", "unknown-inspection-body-after-grant",
                "partial-marker-after-grant", "duplicate-permit", "duplicate-consume", "repeated-phase", "future-phase",
                "foreign-phase-challenge", "foreign-run-directory", "mutated-inspect-request", "mutated-inspect-reply",
                "reply-collision", "observation-failed", "observation-crosses-cutoff", "stop-precedes-inspection",
                "stop-precedes-permit", "execution-cutoff", "cleanup-cutoff", "inspection-limit", "extra-request-field",
                "symlink-request", "cancel-before-consume"]
            var results: [Result] = []
            for name in names { results.append(await exercise(name, root: root)) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: root.appendingPathComponent("results.json"), options: .withoutOverwriting)
            guard results.allSatisfy(\.passed) else { throw Invalid.assertion }
            print("PASS \(results.count) local transport controls; no native acceptance")
        } catch { print("FAIL phase transport controls; inspect preserved output"); exit(1) }
    }
}
