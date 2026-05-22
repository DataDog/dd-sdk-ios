/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - RemoteConfigurationSynchronizer

/// Owns the remote configuration cache and fetch lifecycle.
///
/// Created and started by `DatadogCore` during initialization when a `remoteConfigurationID`
/// is provided. `start(from:connectionProxyDictionary:telemetry:)` fires the initial CDN fetch.
///
/// TODO: Also trigger `start()` on every app foreground transition so remote config
/// is refreshed while the app is in use, not only at SDK init (RFC §Caching Strategy).
internal final class RemoteConfigurationSynchronizer {
    let cache: RemoteConfigurationCache

    init(id: String, directory: Directory) {
        self.cache = RemoteConfigurationCache(id: id, directory: directory)
    }

    /// Constructs the CDN URL for fetching remote configuration.
    ///
    /// - Parameters:
    ///   - id: The remote configuration ID from `Datadog.Configuration.remoteConfigurationID`.
    ///   - host: The CDN hostname from `DatadogSite.remoteConfigurationHost`.
    /// - Returns: URL to GET the config JSON, or `nil` if `id` cannot be percent-encoded.
    static func endpoint(for id: String, host: String) -> URL? {
        // `.urlPathAllowed` leaves `/`, `?`, and `#` unencoded (they are legal in a URL path).
        // Subtract them so an ID containing those characters doesn't produce extra path
        // segments, a query string, or a fragment.
        let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            return nil
        }
        return URL(string: "https://\(host)/v1/\(encoded).json")
    }

    /// Reports any load error from the previous session and fires an async CDN fetch.
    ///
    /// - Parameters:
    ///   - session: Injected only in tests; pass `nil` in production.
    ///   - didComplete: Called when the fetch (and any cache write) is done. Injected only in tests; pass `nil` in production.
    func start(from endpoint: URL, connectionProxyDictionary: [AnyHashable: Any]?, telemetry: Telemetry, session: URLSession? = nil, didComplete: (() -> Void)? = nil) {
        if let error = cache.loadError {
            telemetry.error("[RemoteConfig] Failed to load cached configuration from disk", error: error)
        }
        let fetcher: RemoteConfigurationFetcher
        if let session = session {
            fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: session)
        } else {
            fetcher = RemoteConfigurationFetcher(cache: cache, connectionProxyDictionary: connectionProxyDictionary, telemetry: telemetry)
        }
        fetcher.fetch(from: endpoint, didComplete: didComplete)
    }
}

// MARK: - RemoteConfigurationCache

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

// MARK: - RemoteConfigurationFetcher

/// Fetches the remote configuration JSON document from the CDN and delegates
/// storage to `RemoteConfigurationCache`.
///
/// Rules:
/// - Fetch is always asynchronous — never blocks the caller.
/// - On success (2xx, non-empty body): calls `cache.save(_:)`.
/// - On any failure: reports a telemetry error and leaves the existing cache untouched.
internal final class RemoteConfigurationFetcher {
    private let cache: RemoteConfigurationCache
    private let telemetry: Telemetry
    private let session: URLSession

    init(
        cache: RemoteConfigurationCache,
        telemetry: Telemetry,
        session: URLSession
    ) {
        self.cache = cache
        self.telemetry = telemetry
        self.session = session
    }

    convenience init(
        cache: RemoteConfigurationCache,
        connectionProxyDictionary: [AnyHashable: Any]?,
        telemetry: Telemetry
    ) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.connectionProxyDictionary = connectionProxyDictionary
        self.init(cache: cache, telemetry: telemetry, session: URLSession(configuration: config))
    }

    /// Fires a background GET request to `endpoint`.
    ///
    /// - Parameter endpoint: The CDN URL to fetch from.
    /// - Parameter didComplete: Called when the fetch (and any write) is done.
    ///   Pass `nil` in production; inject a closure in tests to await completion.
    func fetch(from endpoint: URL, didComplete: (() -> Void)? = nil) {
        // TODO RUM-16386: Add ETag-based conditional requests (If-None-Match / 304) and
        // TTL-based revalidation (skip fetch if cached config is < 5 min old).
        let cache = self.cache
        let telemetry = self.telemetry
        let task = session.dataTask(with: endpoint) { data, response, error in
            defer { didComplete?() }

            // 1. Network error
            if let error = error {
                telemetry.error("[RemoteConfig] Network error", error: error)
                return
            }

            // 2. Non-2xx HTTP status
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                // Use a fixed message so all HTTP errors bucket together in telemetry;
                // the status code lives in the error object, not the message string.
                telemetry.error("[RemoteConfig] Non-2xx response", error: NSError(
                    domain: "RemoteConfiguration",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]
                ))
                return
            }

            // 3. Empty body
            guard let data = data, !data.isEmpty else {
                telemetry.error("[RemoteConfig] Empty response body")
                return
            }

            // TODO RUM-16387: Validate the schema before saving

            // All checks passed — persist to disk
            if let error = cache.save(data) {
                telemetry.error("[RemoteConfig] Failed to write remote configuration to disk", error: error)
            }
        }
        task.resume()
    }
}
