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

    /// Fires an async CDN fetch and updates the cache on success.
    ///
    /// - Parameter completionHandler: Called with the fetch result when the operation (and any cache write) is done.
    func sync(_ completionHandler: @escaping (Result<Data, Error>) -> Void) {
        // TODO RUM-16386: Add ETag-based conditional requests (If-None-Match / 304) and
        // TTL-based revalidation (skip fetch if cached config is < 5 min old).

        let endpoint = site.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent(id)
            .appendingPathExtension("json")

        httpClient.fetch(request: URLRequest(url: endpoint)) { result in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))

            case .success(let (http, data)):
                // 1. Non-2xx HTTP status
                guard (200..<300).contains(http.statusCode) else {
                    completionHandler(.failure(RemoteConfigurationError.httpError(http.statusCode)))
                    return
                }

                // 2. Empty body
                guard !data.isEmpty else {
                    completionHandler(.failure(RemoteConfigurationError.emptyBody))
                    return
                }

                // TODO RUM-16387: Validate the schema before saving

                // All checks passed — persist to disk and update in-memory cache.
                // createFile creates or atomically replaces the file, so no existence check needed.
                do {
                    let file = try self.directory.createFile(named: "\(self.id).json")
                    try file.write(data: data)
                    self.cache = .success(data)
                    completionHandler(.success(data))
                } catch {
                    completionHandler(.failure(error))
                }
            }
        }
    }
}

private enum RemoteConfigurationError: Error {
    case httpError(Int)
    case emptyBody
}
