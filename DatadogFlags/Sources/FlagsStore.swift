/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// TODO: FFL-1048 Use the Core SDK’s DataStore instead
internal class FlagsStore {
    private struct State: Codable {
        var flags: [String: FlagAssignment]
        var context: FlagsEvaluationContext
        var date: Date
    }

    var context: FlagsEvaluationContext? {
        state?.context
    }

    @ReadWriteLock
    private var state: State?

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
        state?.flags[key]
    }

    func setFlagAssignments(_ flags: [String: FlagAssignment], for context: FlagsEvaluationContext, date: Date) {
        state = .init(flags: flags, context: context, date: date)
        saveToDisk()
    }

    private func saveToDisk() {
        guard let cacheFileURL = self.cacheFileURL else {
            return
        }

        Self.persistenceQueue.async { [state] in
            guard let state else {
                return
            }
            do {
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
            state = try JSONDecoder().decode(State.self, from: data)
        } catch {
            print("No flags found on disk or error decoding: \(error)")
        }
    }
}
