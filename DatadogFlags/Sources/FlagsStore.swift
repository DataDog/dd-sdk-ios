/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class FlagsStore {
    private var cachedFlags: [String: Any] = [:]
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

    func getFlags() -> [String: Any] {
        return syncQueue.sync { self.cachedFlags }
    }

    func setFlags(_ flags: [String: Any]) {
        setFlags(flags, context: nil)
    }

    func setFlags(_ flags: [String: Any], context: FlagsEvaluationContext?) {
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
        guard let cacheFileURL = self.cacheFileURL else { return }

        Self.persistenceQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            do {
                var cacheData: [String: Any] = [
                    "flags": self.cachedFlags
                ]

                if let metadata = self.flagsMetadata {
                    var metadataDict: [String: Any] = [
                        "fetchedAt": metadata.fetchedAt
                    ]

                    if let context = metadata.context {
                        metadataDict["context"] = [
                            "targetingKey": context.targetingKey,
                            "attributes": context.attributes
                        ]
                    }

                    cacheData["metadata"] = metadataDict
                }

                let data = try JSONSerialization.data(withJSONObject: cacheData, options: [])
                try data.write(to: cacheFileURL, options: .atomic)
            } catch {
                print("Error saving flags to disk: \(error)")
            }
        }
    }

    private func loadFromDisk() {
        guard let cacheFileURL = self.cacheFileURL else { return }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            if let cacheData = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {

                // Load flags
                if let flags = cacheData["flags"] as? [String: Any] {
                    self.cachedFlags = flags
                }

                // Load metadata if available
                if let metadataDict = cacheData["metadata"] as? [String: Any],
                   let fetchedAt = metadataDict["fetchedAt"] as? Double {

                    var context: FlagsEvaluationContext?
                    if let contextDict = metadataDict["context"] as? [String: Any],
                       let targetingKey = contextDict["targetingKey"] as? String,
                       let attributes = contextDict["attributes"] as? [String: Any] {
                        context = FlagsEvaluationContext(targetingKey: targetingKey, attributes: attributes)
                    }

                    self.flagsMetadata = FlagsMetadata(fetchedAt: fetchedAt, context: context)
                }
            } else {
                // Handle legacy cache format (just flags without metadata)
                if let flags = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.cachedFlags = flags
                }
            }
        } catch {
            print("No flags found on disk or error decoding: \(error)")
        }
    }
}
