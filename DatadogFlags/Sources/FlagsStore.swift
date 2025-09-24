/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// TODO: FFL-1048 Use the Core SDK’s DataStore instead
internal class FlagsStore {
    private struct State: Codable {
        let flags: [String: FlagAssignment]
        let metadata: FlagsMetadata?
    }

    private var cachedFlags: [String: FlagAssignment] = [:]
    private var flagsMetadata: FlagsMetadata?
    private let syncQueue = DispatchQueue(label: "com.datadoghq.flags.store", attributes: .concurrent)
    private let cacheFileURL: URL?
    private static let persistenceQueue = DispatchQueue(label: "com.datadoghq.flags.persistence", qos: .background)

    init(withPersistentCache: Bool = true) {
        self.cacheFileURL = withPersistentCache ? Self.findCacheFileURL() : nil
        loadFromDisk()
    }

    private static func findCacheFileURL() -> URL? {
        guard let cacheDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("datadog-flags", isDirectory: true) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: cacheDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Error creating cache directory: \(error)")
            return nil
        }

        return cacheDirectoryURL.appendingPathComponent("flags-cache.json", isDirectory: false)
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        syncQueue.sync {
            self.cachedFlags[key]
        }
    }

    func setFlags(_ flags: [String: FlagAssignment], context: FlagsEvaluationContext? = nil) {
        let timestamp = Date().timeIntervalSince1970 * 1_000 // JavaScript-style timestamp in milliseconds

        syncQueue.sync(flags: .barrier) {
            self.cachedFlags = flags
            self.flagsMetadata = FlagsMetadata(
                fetchedAt: timestamp,
                context: context
            )
            self.saveToDisk()
        }
    }

    func getFlagsMetadata() -> FlagsMetadata? {
        return syncQueue.sync { self.flagsMetadata }
    }

    private func saveToDisk() {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }

        Self.persistenceQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            do {
                let state = State(flags: self.cachedFlags, metadata: self.flagsMetadata)
                let data = try JSONEncoder().encode(state)

                try data.write(to: cacheFileURL, options: .atomic)
            } catch {
                print("Error saving flags to disk: \(error)")
            }
        }
    }

    private func loadFromDisk() {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let state = try JSONDecoder().decode(State.self, from: data)

            self.cachedFlags = state.flags
            self.flagsMetadata = state.metadata
        } catch {
            print("No flags found on disk or error decoding: \(error)")
        }
    }
}
