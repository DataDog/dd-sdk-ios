/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Manages the on-disk cache of the remote configuration JSON document.
///
/// The cache is a single file named after the remote configuration ID, stored at
/// the root of the SDK's private core directory:
///
///     /Library/Caches/com.datadoghq/v2/<instance-uuid>/<config-id>.json
///
/// The file contains raw JSON bytes exactly as received from the CDN.
/// Parsing and applying those values is handled separately.
internal final class RemoteConfigurationCache {
    private let fileURL: URL

    /// Raw JSON bytes from the previous CDN fetch, read synchronously at init.
    /// `nil` when no cache exists yet (first launch, or no file on disk).
    /// Consumed by the config-application layer once parsing and applying remote values is implemented.
    private(set) var data: Data?

    /// Error encountered when reading the cache file at init, if any.
    /// `nil` when the file was absent (expected on first launch) or read successfully.
    private(set) var loadError: Error?

    init(id: String, directory: Directory) {
        self.fileURL = directory.url.appendingPathComponent("\(id).json")
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        let (data, error) = Self.readFromDisk(at: fileURL)
        self.data = data
        self.loadError = error
    }

    // MARK: - Private

    private static func readFromDisk(at url: URL) -> (Data?, Error?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (nil, nil)
        }
        do {
            return (try Data(contentsOf: url), nil)
        } catch {
            return (nil, error)
        }
    }

    // MARK: - Internal

    /// Writes raw CDN response bytes to disk atomically and updates the in-memory copy.
    /// Called only on a successful CDN response — never on failure.
    /// In-memory `data` is only updated when the disk write succeeds, keeping
    /// the two in sync.
    /// - Returns: `nil` on success, or the underlying write error on failure.
    @discardableResult
    func save(_ data: Data) -> Error? {
        do {
            try data.write(to: fileURL, options: .atomic)
            self.data = data
            return nil
        } catch {
            // self.data is intentionally NOT updated so in-memory state stays
            // consistent with what is actually on disk.
            return error
        }
    }
}
