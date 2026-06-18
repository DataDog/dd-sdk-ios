/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Provides the last successfully fetched remote configuration.
/// Refreshes when started and when the app enters foreground.
internal final class RemoteConfigurationProvider {
    let id: String
    let site: DatadogSite
    let directory: Directory
    let httpClient: HTTPClient
    private let notificationCenter: NotificationCenter
    @ReadWriteLock
    private var foregroundObserver: NSObjectProtocol?

    /// The result of the last cache read or CDN fetch.
    /// `.success(remoteConfiguration)` — remote configuration is available.
    /// `.failure` — no cache yet, or a read/write error.
    @ReadWriteLock
    private(set) var cache: Result<RemoteConfiguration, RemoteConfigurationError> = .failure(.diskError)

    var remoteConfiguration: RemoteConfiguration? {
        try? cache.get()
    }

    init(
        id: String,
        site: DatadogSite,
        directory: Directory,
        httpClient: HTTPClient,
        notificationCenter: NotificationCenter
    ) {
        self.id = id
        self.site = site
        self.directory = directory
        self.httpClient = httpClient
        self.notificationCenter = notificationCenter
    }

    func start(_ completionHandler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        let cached = Self.readCache(id: id, from: directory)
        if let cached {
            cache = cached
            completionHandler(cached)
        }

        #if canImport(UIKit)
        foregroundObserver = notificationCenter.addObserver(
            forName: ApplicationNotifications.willEnterForeground,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.sync { _ in }
        }
        #endif

        sync(cached == nil ? completionHandler : { _ in })
    }

    func stop() {
        #if canImport(UIKit)
        var observer: NSObjectProtocol?
        _foregroundObserver.mutate {
            observer = $0
            $0 = nil
        }

        if let observer {
            notificationCenter.removeObserver(observer)
        }
        #endif
    }

    // MARK: - Private

    private static func readCache(
        id: String,
        from directory: Directory
    ) -> Result<RemoteConfiguration, RemoteConfigurationError>? {
        let fileName = "\(id).json"
        guard directory.hasFile(named: fileName) else {
            return nil
        }

        let data: Data
        do {
            data = try directory.file(named: fileName).read()
        } catch {
            return .failure(.diskError)
        }

        return decode(data)
    }

    private static func decode(_ data: Data) -> Result<RemoteConfiguration, RemoteConfigurationError> {
        do {
            return .success(try JSONDecoder().decode(RemoteConfiguration.self, from: data))
        } catch {
            return .failure(.decodingError(error))
        }
    }

    /// Fires an async CDN fetch and updates the cache on success.
    private func sync(_ completionHandler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
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

        httpClient.send(request: request, delegate: nil) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .failure(let error):
                completionHandler(.failure(.networkError(error)))

            case .success(let (http, data)):
                // 1. Not Modified — existing cache is still valid
                if http.statusCode == 304, case .success = self.cache {
                    completionHandler(self.cache)
                    return
                }

                // 2. Non-2xx HTTP status
                guard (200..<300).contains(http.statusCode) else {
                    completionHandler(.failure(.httpError(http.statusCode)))
                    return
                }

                // 3. Empty body
                guard let data = data, !data.isEmpty else {
                    completionHandler(.failure(.emptyBody))
                    return
                }

                let remoteConfiguration: RemoteConfiguration
                switch Self.decode(data) {
                case .success(let decodedRemoteConfiguration):
                    remoteConfiguration = decodedRemoteConfiguration
                case .failure(let error):
                    completionHandler(.failure(error))
                    return
                }

                // All checks passed — persist to disk and update in-memory cache.
                // File.write uses .atomic (write to temp, then rename), so the update is
                // all-or-nothing: the existing file is never left in a truncated state.
                do {
                    try File(url: self.directory.url.appendingPathComponent("\(self.id).json")).write(data: data)
                    let result: Result<RemoteConfiguration, RemoteConfigurationError> = .success(remoteConfiguration)
                    self.cache = result

                    // Store ETag for conditional requests on the next sync.
                    // If the response has no ETag, delete any stale validator so we
                    // never send If-None-Match for a different representation.
                    let etagFileName = "\(self.id).etag"
                    if let etag = http.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "etag" })?.value as? String {
                        let etagFile = self.directory.hasFile(named: etagFileName)
                            ? (try? self.directory.file(named: etagFileName))
                            : (try? self.directory.createFile(named: etagFileName))
                        try? etagFile?.write(data: Data(etag.utf8))
                    } else {
                        // try? silently handles the case where the file does not exist
                        try? self.directory.file(named: etagFileName).delete()
                    }
                    completionHandler(result)
                } catch {
                    completionHandler(.failure(.diskError))
                }
            }
        }
    }
}

internal enum RemoteConfigurationError: Error, LocalizedError {
    case networkError(Error)
    case httpError(Int)
    case emptyBody
    case decodingError(Error)
    case diskError

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .httpError(let code): return "Non-2xx response: HTTP \(code)"
        case .emptyBody: return "Empty response body"
        case .decodingError(let error): return "Remote configuration decoding failed: \(error.localizedDescription)"
        case .diskError: return "Remote configuration disk read/write failed"
        }
    }
}
