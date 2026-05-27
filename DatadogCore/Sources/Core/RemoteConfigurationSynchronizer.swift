/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Owns the remote configuration cache and fetch lifecycle.
///
/// Created by `DatadogCore` during initialization when a `remoteConfigurationID` is provided.
/// Call `sync(_:)` to fire a CDN fetch and update the cache.
///
/// TODO: Also trigger `sync()` on every app foreground transition so remote config
/// is refreshed while the app is in use, not only at SDK init (RFC §Caching Strategy).
internal final class RemoteConfigurationSynchronizer {
    let id: String
    let site: DatadogSite
    let directory: Directory
    let httpClient: HTTPClient

    /// The result of the last cache read or CDN fetch.
    /// `.success(data)` — data is available.
    /// `.failure` — no cache yet, or a read/write error.
    @ReadWriteLock
    private(set) var cache: Result<Data, Error>

    private static let ttl: TimeInterval = 5 * 60

    init(id: String, site: DatadogSite, directory: Directory, httpClient: HTTPClient) {
        self.id = id
        self.site = site
        self.directory = directory
        self.httpClient = httpClient
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        self._cache = ReadWriteLock(wrappedValue: Self.readCache(id: id, from: directory))
    }

    // MARK: - Private

    private static func readCache(id: String, from directory: Directory) -> Result<Data, Error> {
        do {
            return .success(try directory.file(named: "\(id).json").read())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Internal

    /// Fires a CDN fetch and updates the cache on success.
    ///
    /// The completion handler may be called synchronously on the caller's thread when
    /// a fresh cached value is available (TTL not exceeded). Otherwise it is called
    /// asynchronously on the URLSession callback queue.
    ///
    /// - Parameter completionHandler: Called with the fetch result when the operation (and any cache write) is done.
    func sync(_ completionHandler: @escaping (Result<Data, Error>) -> Void) {
        // Skip fetch if cached config is less than 5 minutes old.
        // The TTL clock resets only when new data is written (2xx response).
        // A 304 does not update modifiedAt, so the next sync will still hit the network —
        // this is intentional: the 5-minute window measures time since the last confirmed write.
        if case .success = cache,
           let date = try? directory.file(named: "\(id).json").modifiedAt(),
           Date().timeIntervalSince(date) < Self.ttl {
            completionHandler(cache)
            return
        }

        // Build request with conditional ETag header if a previous ETag is stored.
        // Only send If-None-Match when the cache is usable — if cache is .failure,
        // a 304 response would leave us with no data to serve.
        var request = URLRequest(url: site.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent(id)
            .appendingPathExtension("json"))

        if case .success = cache,
           let data = try? directory.file(named: "\(id).etag").read(),
           let etag = String(data: data, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        httpClient.fetch(request: request) { result in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))

            case .success(let (http, data)):
                // 1. Not Modified — existing cache is still valid
                if http.statusCode == 304 {
                    completionHandler(self.cache)
                    return
                }

                // 2. Non-2xx HTTP status
                guard (200..<300).contains(http.statusCode) else {
                    completionHandler(.failure(RemoteConfigurationError.httpError(http.statusCode)))
                    return
                }

                // 3. Empty body
                guard !data.isEmpty else {
                    completionHandler(.failure(RemoteConfigurationError.emptyBody))
                    return
                }

                // TODO RUM-16387: Validate the schema before saving

                // All checks passed — persist to disk and update in-memory cache.
                // File.write uses .atomic (write to temp, then rename), so the update is
                // all-or-nothing: the existing file is never left in a truncated state.
                do {
                    try File(url: self.directory.url.appendingPathComponent("\(self.id).json")).write(data: data)
                    self.cache = .success(data)

                    // Store ETag for conditional requests on the next sync.
                    // allHeaderFields["ETag"] uses case-sensitive Swift String equality, so we
                    // search case-insensitively to handle servers that vary capitalisation.
                    let etag = http.allHeaderFields
                        .first { ($0.key as? String)?.caseInsensitiveCompare("ETag") == .orderedSame }
                        .flatMap { $0.value as? String }
                    if let etag = etag {
                        try? File(url: self.directory.url.appendingPathComponent("\(self.id).etag")).write(data: Data(etag.utf8))
                    }

                    completionHandler(.success(data))
                } catch {
                    completionHandler(.failure(error))
                }
            }
        }
    }
}

private enum RemoteConfigurationError: Error, LocalizedError {
    case httpError(Int)
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Non-2xx response: HTTP \(code)"
        case .emptyBody: return "Empty response body"
        }
    }
}
