// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

/// Transport for three host evidence barriers. An opaque observation or display
/// digest never qualifies ownership; the host oracle and synchronous guard do.
@MainActor
internal final class ProbeSceneBackgroundPhase {
    static let names = ["initial-both-foreground", "A-background-B-foreground", "A-foreground-B-foreground"]
    static let maximumInspections = 24
    struct Challenge: Codable, Equatable {
        let identity: ProbeSceneBackgroundControl.Identity
        let phase: Int
        let name: String
        let challengeID: String
        let maximumInspections: Int
    }
    struct Request: Codable {
        let challenge: Challenge
        let sequence: Int
        let commandID: String
        let operation: String
        let previousReplySHA256: String
        let inspectedReplySHA256: String?
        let displayReceiptSHA256: String?
    }
    struct Reply: Codable {
        let challenge: Challenge
        let sequence: Int
        let commandID: String
        let requestSHA256: String
        let operation: String
        let outcome: String
        let observation: Data?
        let observationSHA256: String?
        let inspectedReplySHA256: String?
        let displayReceiptSHA256: String?
    }
    enum State { case absent, waiting, granted, consumed, stopped }
    enum Failure: Error { case stopped, phase, file, request, replay, publication, pending }
    let control: ProbeSceneBackgroundControl
    private(set) var state = State.absent
    private(set) var challenge: Challenge?
    private(set) var failure: String?
    private let observe: () throws -> Data
    private let clock: () -> Int64
    private var busy = false
    private var nextPhase = 0
    private var sequence = 1
    private var inspections = 0
    private var commands = Set<String>()
    private var files: [String: String] = [:]
    private var previousReply = ""
    private var lastInspection: String?
    private var lastRequest: String?
    private var pendingRequest: String?

    init(control: ProbeSceneBackgroundControl, clock: @escaping () -> Int64, observe: @escaping () throws -> Data) {
        self.control = control
        self.clock = clock
        self.observe = observe
    }

    private func fail(_ error: Error) -> Error {
        failure = failure ?? "background phase transport failed"
        state = .stopped
        control.stopForPhaseFailure(failure ?? "background phase transport failed")
        return error
    }

    private func checkActive() throws {
        guard failure == nil, !Task.isCancelled, control.admissionFailure(now: clock()) == nil else {
            throw fail(Failure.stopped)
        }
    }

    private var prefix: String { "phase-\(challenge?.phase ?? -1)/" }

    private func verifyDirectory() throws -> URL {
        let url = control.directory.appendingPathComponent(prefix, isDirectory: true)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.file }
        return url
    }

    private func read(_ name: String, limit: Int = ProbeSceneBackgroundControl.maximumBytes) throws -> Data? {
        _ = try verifyDirectory()
        return try control.readPhaseFile(prefix + name, limit: limit)
    }

    private func write(_ bytes: Data, name: String) throws {
        _ = try verifyDirectory()
        try control.writePhaseFile(bytes, name: prefix + name)
        files[name] = ProbeSceneBackgroundControl.sha(bytes)
    }

    private func verifyPublished() throws {
        for (name, hash) in files {
            guard let bytes = try read(name), ProbeSceneBackgroundControl.sha(bytes) == hash else { throw Failure.file }
        }
    }

    func begin(_ index: Int) throws {
        do {
            try checkActive()
            guard !busy, index == nextPhase, Self.names.indices.contains(index),
                  state == .absent || state == .consumed else { throw Failure.phase }
            busy = true
            defer { busy = false }
            let value = Challenge(identity: control.identity, phase: index, name: Self.names[index],
                                  challengeID: UUID().uuidString.lowercased(), maximumInspections: Self.maximumInspections)
            challenge = value
            files = [:]; sequence = 1; inspections = 0
            lastInspection = nil; lastRequest = nil; pendingRequest = nil
            let directory = control.directory.appendingPathComponent(prefix, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.file }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let bytes = try ProbeSceneBackgroundControl.encode(value)
            try write(bytes, name: "challenge.json")
            try checkActive()
            previousReply = ProbeSceneBackgroundControl.sha(bytes)
            state = .waiting
        } catch { throw fail(error) }
    }

    /// Polling the base first gives STOP priority even when a permit is visible.
    func poll() throws {
        do {
            guard !busy else { throw Failure.phase }
            busy = true
            defer { busy = false }
            try control.poll(now: clock())
            guard control.phase == .armed, control.failure == nil else {
                if challenge != nil { state = .stopped }
                return
            }
            guard challenge != nil else { return }
            try checkActive()
            try verifyPublished()
            guard let marker = try read("command.request", limit: 64) else { return }
            if marker.count < 64 {
                guard pendingRequest == nil, state == .waiting else { throw Failure.pending }
                return
            }
            guard let digest = String(data: marker, encoding: .utf8), ProbeSceneBackgroundControl.digest(digest) else { throw Failure.request }
            if let pendingRequest { guard pendingRequest == digest else { throw Failure.pending } }
            if lastRequest == digest { return }
            guard state == .waiting else { throw Failure.replay }
            pendingRequest = digest
            guard let bytes = try read(digest + ".json"), ProbeSceneBackgroundControl.sha(bytes) == digest else { return }
            let request = try JSONDecoder().decode(Request.self, from: bytes)
            guard try ProbeSceneBackgroundControl.encode(request) == bytes, request.challenge == challenge,
                  request.sequence == sequence, request.previousReplySHA256 == previousReply,
                  ProbeSceneBackgroundControl.uuid(request.commandID), !commands.contains(request.commandID) else { throw Failure.request }
            let reply: Reply
            if request.operation == "inspect" {
                guard request.inspectedReplySHA256 == nil, request.displayReceiptSHA256 == nil,
                      inspections < Self.maximumInspections else { throw Failure.request }
                let observation = try observe()
                guard !observation.isEmpty, observation.count <= ProbeSceneBackgroundControl.maximumBytes else { throw Failure.publication }
                try checkActive()
                reply = .init(challenge: request.challenge, sequence: sequence, commandID: request.commandID,
                              requestSHA256: digest, operation: "inspect", outcome: "observed",
                              observation: observation, observationSHA256: ProbeSceneBackgroundControl.sha(observation),
                              inspectedReplySHA256: nil, displayReceiptSHA256: nil)
            } else {
                guard request.operation == "permit", let lastInspection,
                      request.inspectedReplySHA256 == lastInspection, previousReply == lastInspection,
                      let display = request.displayReceiptSHA256, ProbeSceneBackgroundControl.digest(display) else { throw Failure.request }
                reply = .init(challenge: request.challenge, sequence: sequence, commandID: request.commandID,
                              requestSHA256: digest, operation: "permit", outcome: "granted",
                              observation: nil, observationSHA256: nil,
                              inspectedReplySHA256: lastInspection, displayReceiptSHA256: display)
            }
            let result = try ProbeSceneBackgroundControl.encode(reply)
            try checkActive()
            try write(result, name: digest + ".reply.json")
            try checkActive()
            // No permission or sequence advances until its actual reply is written.
            files[digest + ".json"] = digest
            commands.insert(request.commandID)
            previousReply = ProbeSceneBackgroundControl.sha(result)
            lastRequest = digest; pendingRequest = nil; sequence += 1
            if request.operation == "inspect" { inspections += 1; lastInspection = previousReply }
            else { state = .granted }
        } catch { throw fail(error) }
    }

    func consume(_ index: Int) throws {
        do {
            try poll()
            try checkActive()
            guard state == .granted, challenge?.phase == index, pendingRequest == nil,
                  let lastRequest, let marker = try read("command.request", limit: 64),
                  String(data: marker, encoding: .utf8) == lastRequest else { throw Failure.phase }
            let names = try FileManager.default.contentsOfDirectory(atPath: verifyDirectory().path)
            // Body-first transport may have staged a newer command without moving
            // the marker yet. Such an unknown outcome cannot authorize dispatch.
            guard Set(names) == Set(files.keys).union(["command.request"]) else { throw Failure.pending }
            try write(ProbeSceneBackgroundControl.encode([
                "permitRequestSHA256": lastRequest, "permitReplySHA256": previousReply
            ]), name: "consumed.json")
            try checkActive()
            state = .consumed
            nextPhase += 1
        } catch { throw fail(error) }
    }
}
