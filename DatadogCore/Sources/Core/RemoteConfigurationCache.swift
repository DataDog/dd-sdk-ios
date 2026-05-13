/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Manages the on-disk cache of the remote configuration JSON document.
///
/// The cache is a single file `remote-config.json` stored at the root of
/// the SDK's private core directory:
///
///     /Library/Caches/com.datadoghq/v2/<instance-uuid>/remote-config.json
///
/// The file contains raw JSON bytes exactly as received from the CDN.
/// Parsing and applying those values is handled separately.
internal final class RemoteConfigurationCache {
    private static let fileName = "remote-config.json"

    private let fileURL: URL

    /// Raw JSON bytes from the previous CDN fetch, read synchronously at init.
    /// `nil` when no cache exists yet (first launch, or remoteConfigurationID was never set).
    /// Consumed by the config-application layer in a follow-on ticket (out of scope for RUM-16084).
    private(set) var data: Data?

    init(directory: Directory) {
        self.fileURL = directory.url.appendingPathComponent(Self.fileName)
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        self.data = Self.readFromDisk(at: fileURL)
    }

    // MARK: - Private

    private static func readFromDisk(at url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    // MARK: - Internal

    /// Writes raw CDN response bytes to disk atomically and updates the in-memory copy.
    /// Called only on a successful CDN response — never on failure.
    /// Write errors are swallowed silently; the cache is best-effort.
    func save(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
        self.data = data
    }
}
