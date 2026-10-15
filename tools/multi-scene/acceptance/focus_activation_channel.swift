/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit

/// Private fixture transport. No SDK calls, UI input or process teardown.
@MainActor
internal final class ProbeFocusControl {
    struct Identity: Codable, Equatable {
        let schemaVersion: Int
        let runID: String
        let processID: Int32
        let scenarioID: String
        let profile: String
        let sourceRevision: String
        let installedCodeSHA256: String
        let challengeID: String
        let executionDeadlineMilliseconds: Int64
        let cleanupDeadlineMilliseconds: Int64
    }
    struct Request: Codable, Equatable {
        let identity: Identity
        let commandID: String
        let operation: String
    }
    struct Driver: Codable {
        let requested: Bool
        let stopped: Bool
        let terminal: Data?
    }
    struct Observation: Codable {
        let before: Data
        let after: Data
        let idle: Bool
        let reason: String?
    }
    struct Reply: Codable {
        let identity: Identity
        let requestSHA256: String
        let commandID: String
        let outcome: String
        let driver: Driver
        let observation: Observation?
        let failure: String?
    }
    enum Phase { case waiting, armed, stopping, closed }
    enum Failure: Error { case identity, file, request, replay }
    nonisolated static let maximumBytes = 1_048_576
    static let scenarioID = "windows.focus-activation-only"
    static let profile = "physical-focus-activation-only"
    let identity: Identity
    let directory: URL
    private(set) var phase = Phase.waiting
    private(set) var failure: String?
    private let observe: (String) throws -> Observation
    private let stop: () -> Void
    private let driver: () -> Driver
    private var publications: [String: String] = [:]
    private var commands = Set<String>()
    private var pendingArm: (Request, String)?
    private var pendingStop: (Request, String)?
    private var lastObservation: Observation?

    init(directory: URL, identity: Identity, now: Int64,
         observe: @escaping (String) throws -> Observation,
         stop: @escaping () -> Void, driver: @escaping () -> Driver) throws {
        guard identity.schemaVersion == 1, identity.processID > 0,
              identity.runID.range(of: "^[a-z0-9-]{1,96}$", options: .regularExpression) != nil,
              identity.scenarioID == Self.scenarioID, identity.profile == Self.profile,
              identity.sourceRevision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              Self.digest(identity.installedCodeSHA256), Self.uuid(identity.challengeID),
              now > 0, now < identity.executionDeadlineMilliseconds,
              identity.executionDeadlineMilliseconds < identity.cleanupDeadlineMilliseconds,
              identity.cleanupDeadlineMilliseconds - now <= 10_800_000 else { throw Failure.identity }
        self.identity = identity; self.directory = directory
        self.observe = observe; self.stop = stop; self.driver = driver
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.file }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try write(Self.encode(identity), name: "challenge.json")
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func sha(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func digest(_ value: String) -> Bool { value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func uuid(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }

    private func verifyDirectory() throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.file }
    }
    private func read(_ name: String, limit: Int = maximumBytes) throws -> Data? {
        try verifyDirectory()
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw Failure.file }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw Failure.file }
        return bytes
    }
    private func write(_ bytes: Data, name: String) throws {
        try verifyDirectory()
        let url = directory.appendingPathComponent(name)
        guard bytes.count <= Self.maximumBytes, !FileManager.default.fileExists(atPath: url.path) else { throw Failure.file }
        try bytes.write(to: url, options: .atomic)
    }
    private func stopDriver(_ reason: String? = nil) {
        if failure == nil { failure = reason }
        if phase != .closed { phase = .stopping }
        stop() // Idempotent; seals future work before awaiting the original task.
    }
    private func reply(_ item: (Request, String), outcome: String, observation: Observation? = nil) throws {
        let value = Reply(identity: identity, requestSHA256: item.1, commandID: item.0.commandID,
                          outcome: outcome, driver: driver(), observation: observation, failure: failure)
        try write(Self.encode(value), name: item.1 + ".reply.json")
    }
    private func consume(_ operation: String) throws -> (Request, String)? {
        guard let marker = try read(operation + ".request", limit: 64),
              let digest = String(data: marker, encoding: .utf8), Self.digest(digest) else { return nil }
        if let previous = publications[operation] {
            guard previous == digest else { throw Failure.replay }
            return nil
        }
        // Partial CoreDevice publication stays pending until the original cutoff.
        guard let bytes = try read(digest + ".json"), Self.sha(bytes) == digest else { return nil }
        publications[operation] = digest
        let request = try JSONDecoder().decode(Request.self, from: bytes)
        guard try Self.encode(request) == bytes, request.identity == identity,
              request.operation == operation, Self.uuid(request.commandID) else { throw Failure.request }
        guard commands.insert(request.commandID).inserted else { throw Failure.replay }
        return (request, digest)
    }

    func admissionFailure(now: Int64) -> String? {
        if now >= identity.executionDeadlineMilliseconds { stopDriver("execution cutoff expired") }
        return phase == .armed && failure == nil ? nil : (failure ?? "focus channel is not armed")
    }

    /// Called from the fixture's single MainActor pump. No waits block that actor.
    func poll(now: Int64) throws {
        guard phase != .closed else { return }
        if now >= identity.cleanupDeadlineMilliseconds {
            stopDriver("cleanup cutoff expired")
            if let item = pendingArm { try reply(item, outcome: "rejected", observation: lastObservation); pendingArm = nil }
            if let item = pendingStop { try reply(item, outcome: "rejected", observation: lastObservation); pendingStop = nil }
            try write(Self.encode(Reply(identity: identity, requestSHA256: String(repeating: "0", count: 64),
                commandID: identity.challengeID, outcome: "expired", driver: driver(),
                observation: lastObservation, failure: failure)), name: "expired.json")
            phase = .closed
            return
        }
        if now >= identity.executionDeadlineMilliseconds { stopDriver("execution cutoff expired") }
        do {
            // Stop always wins if both commands become visible in one tick.
            if let item = try consume("stop") { pendingStop = item; stopDriver() }
            if phase != .stopping || failure == nil, let item = try consume("arm") {
                if phase == .waiting && failure == nil { pendingArm = item }
                else { try reply(item, outcome: "rejected") }
            }
            if phase == .stopping, let item = pendingArm { try reply(item, outcome: "rejected"); pendingArm = nil }
            if let item = pendingArm, phase == .waiting {
                let observation = try observe("arm"); lastObservation = observation
                if observation.idle {
                    let state = driver()
                    guard !state.requested, !state.stopped else { throw Failure.request }
                    // Publish before granting the first driver step.
                    pendingArm = nil
                    try reply(item, outcome: "armed", observation: observation)
                    phase = .armed
                }
            }
            if let item = pendingStop, phase == .stopping {
                let state = driver()
                if state.requested && state.stopped {
                    let observation = try observe("stop"); lastObservation = observation
                    if observation.idle {
                        try reply(item, outcome: "stopped-idle", observation: observation)
                        pendingStop = nil; phase = .closed
                    }
                }
            }
        } catch {
            stopDriver("focus command or evidence publication failed")
            throw error
        }
    }
}
