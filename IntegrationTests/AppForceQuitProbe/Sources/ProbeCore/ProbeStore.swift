/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Darwin
import Foundation

internal enum ProbeStoreError: Error { case ioFailure, alreadyConsumed }

// Probe-only synchronous checkpointing. Device trials must measure its callback cost.
// The dirty marker makes an interrupted transaction ineligible on relaunch.
internal final class ProbeStore {
    let directory: URL
    var beforeCommit: (() throws -> Void)?

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> (run: ProbeRun?, reliable: Bool) {
        let dirty = directory.appendingPathComponent("checkpoint.pending")
        let file = directory.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return (nil, !FileManager.default.fileExists(atPath: dirty.path))
        }
        do {
            let run = try JSONDecoder().decode(ProbeRun.self, from: Data(contentsOf: file))
            return (run, run.schemaVersion == 1 && !FileManager.default.fileExists(atPath: dirty.path))
        } catch {
            return (nil, false)
        }
    }

    @discardableResult
    func checkpoint(_ run: ProbeRun) throws -> Double {
        let begin = ProcessInfo.processInfo.systemUptime
        try atomic(Data("pending".utf8), to: directory.appendingPathComponent("checkpoint.pending"))
        try beforeCommit?()
        try atomic(try JSONEncoder().encode(run), to: directory.appendingPathComponent("current.json"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("checkpoint.pending"))
        try syncDirectory()
        return (ProcessInfo.processInfo.systemUptime - begin) * 1_000
    }

    func atomic(_ data: Data, to target: URL) throws {
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.synchronize()
        guard rename(temporary.path, target.path) == 0 else { throw ProbeStoreError.ioFailure }
        try syncDirectory()
    }

    private func syncDirectory() throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw ProbeStoreError.ioFailure }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ProbeStoreError.ioFailure }
    }

    // O_EXCL gives a durable consume-before-write receipt across repeated launches.
    func consume(_ id: UUID) throws {
        let path = directory.appendingPathComponent("consumed-\(id.uuidString)").path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw ProbeStoreError.alreadyConsumed }
            throw ProbeStoreError.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ProbeStoreError.ioFailure }
        try syncDirectory()
    }
}

internal struct ProbeView: Codable {
    var sessionID: String
    var viewID: String
    var consent: Bool
    var sampled: Bool
    var frustrations: Bool
}

internal struct ProbeReportingGates {
    var consent: Bool
    var frustrations: Bool
}

internal enum ProbeReturnPath {
    // Local preparation only. A real writer and intake validation remain gated on raw feasibility.
    static func prepare(
        previous: ProbeView?,
        current: ProbeReportingGates,
        verdict: ProbeVerdict,
        runID: UUID,
        store: ProbeStore
    ) throws -> Data? {
        guard let previous = previous,
            verdict.outcome == "candidate", previous.consent, previous.sampled, previous.frustrations,
            current.consent, current.frustrations, UUID(uuidString: previous.sessionID) != nil,
            UUID(uuidString: previous.viewID) != nil
        else { return nil }
        try store.consume(runID)
        let action: [String: Any] = [
            "type": "action", "session": ["id": previous.sessionID], "view": ["id": previous.viewID],
            "action": [
                "id": UUID().uuidString, "type": "custom", "target": ["name": "App force quit probe"]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: action, options: [.sortedKeys])
    }
}
