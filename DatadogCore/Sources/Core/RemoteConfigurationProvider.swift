/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Fetches and caches remote configuration from the Datadog CDN.
///
/// On `start(_:)`, the provider immediately delivers any previously cached configuration
/// from disk, then fires an async CDN request to refresh it. On UIKit platforms it also
/// re-syncs whenever the app returns to the foreground, so long-lived sessions always
/// converge on the latest configuration without requiring a restart.
///
/// ## Caching
/// A successful fetch is persisted as `<id>.json` inside the supplied `directory`.
/// The accompanying HTTP ETag is stored in `<id>.etag` and sent back as `If-None-Match`
/// on subsequent requests, turning unchanged responses into lightweight 304s that skip
/// body transfer and re-parse entirely.
///
/// ## Threading
/// - The synchronous cache read in `start` runs on the caller's thread.
/// - The network completion and all `handler` calls are dispatched on an
///   internal URLSession delegate queue (not the main thread).
///
/// ## Lifecycle
/// Call `stop()` (or let the instance deinit) to unsubscribe from foreground
/// notifications and prevent further `handler` invocations.
internal final class RemoteConfigurationProvider {
    let id: String
    let site: DatadogSite
    let directory: Directory
    let httpClient: HTTPClient

    private let notificationCenter: NotificationCenter
    private let dateProvider: DateProvider
    private let minimumSyncInterval: TimeInterval = 300
    @ReadWriteLock
    private var lastSyncDate: Date? = nil
    @ReadWriteLock
    private var foregroundObserver: NSObjectProtocol?

    init(
        id: String,
        site: DatadogSite,
        directory: Directory,
        httpClient: HTTPClient,
        notificationCenter: NotificationCenter,
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.id = id
        self.site = site
        self.directory = directory
        self.httpClient = httpClient
        self.notificationCenter = notificationCenter
        self.dateProvider = dateProvider
    }

    /// Starts the provider.
    ///
    /// `handler` is **not** a one-shot completion — it is invoked every time a configuration
    /// result becomes available:
    /// - synchronously with the cached configuration, if one exists on disk;
    /// - asynchronously when the CDN request completes (success or failure);
    /// - on UIKit platforms, again on each `UIApplication.willEnterForegroundNotification`
    ///   that triggers a refresh.
    ///
    /// Each invocation carries the latest result, so callers should replace the previously
    /// delivered value rather than accumulate.
    ///
    /// - Parameter handler: Called with `.success` when configuration is available
    ///   (from cache or network), or `.failure` if a read or fetch error occurs.
    func start(_ handler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        readCache().map(handler)

#if canImport(UIKit)
        foregroundObserver = notificationCenter.addObserver(
            forName: ApplicationNotifications.willEnterForeground,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }
            if let last = self.lastSyncDate {
                let elapsed = self.dateProvider.now.timeIntervalSince(last)
                if elapsed >= 0, elapsed < self.minimumSyncInterval {
                    return
                }
            }
            self.sync(handler)
        }
#endif

        sync(handler)
    }

    deinit {
        stop()
    }

    /// Stops the provider.
    ///
    /// Unsubscribes from foreground notifications so that in-flight or future syncs
    /// no longer invoke the completion handler passed to `start(_:)`. Any network
    /// request already in flight may still complete, but its result is discarded
    /// because the `[weak self]` capture in the HTTP callback resolves to `nil`.
    ///
    /// Safe to call multiple times and from any thread.
    func stop() {
        _foregroundObserver.mutate { observer in
#if canImport(UIKit)
            observer.map { notificationCenter.removeObserver($0) }
#endif
            observer = nil
        }
    }

    // MARK: - Private

    private func readCache() -> Result<RemoteConfiguration, RemoteConfigurationError>? {
        let cacheFilename = "\(id).json"
        guard directory.hasFile(named: cacheFilename) else {
            return nil
        }

        do {
            let data = try directory.file(named: cacheFilename).read()
            let remoteConfiguration = try JSONDecoder().decode(RemoteConfiguration.self, from: data)
            return .success(remoteConfiguration)
        } catch let error as DecodingError {
            return .failure(.decodingError(error))
        } catch {
            return .failure(.internalError(error))
        }
    }

    /// Fires an async CDN fetch and persists the configuration on success.
    private func sync(_ handler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
        let cacheFilename = "\(id).json"
        let etagFilename = "\(id).etag"

        // Build request with conditional ETag header if a previous ETag is stored.
        var request = URLRequest(
            url: site.remoteConfigurationEndpoint
                .appendingPathComponent("v1")
                .appendingPathComponent(id)
                .appendingPathExtension("json")
        )

        if let file = try? directory.file(named: etagFilename) {
            do {
                try String(data: file.read(), encoding: .utf8)
                    .map { request.setValue($0, forHTTPHeaderField: "If-None-Match") }
            } catch {
                handler(.failure(.etagError(error)))
            }
        }

        httpClient.send(request: request, delegate: nil) { [weak self] result in
            guard let self else {
                return
            }

            do {
                let (http, data) = try result
                    .mapError { RemoteConfigurationError.networkError($0) }
                    .get()

                if http.statusCode == 304 {
                    self.lastSyncDate = self.dateProvider.now
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    throw RemoteConfigurationError.httpError(http.statusCode)
                }

                do {
                    // Persist ETag before decoding — the ETag belongs to the HTTP response,
                    // not to whether we could parse the body. This prevents re-fetching a
                    // known-bad payload on every sync; we recover when the server updates.
                    if let etag = http.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "etag" })?.value as? String {
                        try self.write(Data(etag.utf8), to: etagFilename)
                    } else if let file = try? directory.file(named: etagFilename) {
                        // Only delete a validator that actually exists; "nothing to delete" is not an error.
                        try file.delete()
                    }
                } catch {
                    handler(.failure(.etagError(error)))
                }

                guard let data, !data.isEmpty else {
                    throw RemoteConfigurationError.emptyBody
                }

                let remoteConfiguration = try JSONDecoder().decode(RemoteConfiguration.self, from: data)

                // All checks passed — persist to disk.
                // File.write uses .atomic (write to temp, then rename), so the update is
                // all-or-nothing: the existing file is never left in a truncated state.
                try self.write(data, to: cacheFilename)
                self.lastSyncDate = self.dateProvider.now

                handler(.success(remoteConfiguration))
            } catch let error as RemoteConfigurationError {
                handler(.failure(error))
            } catch let error as DecodingError {
                handler(.failure(.decodingError(error)))
            } catch {
                handler(.failure(.internalError(error)))
            }
        }
    }

    private func write(_ data: Data, to filename: String) throws {
        let file = directory.hasFile(named: filename)
            ? try directory.file(named: filename)
            : try directory.createFile(named: filename)
        try file.write(data: data)
    }
}

internal enum RemoteConfigurationError: Error, LocalizedError {
    case networkError(Error)
    case httpError(Int)
    case emptyBody
    case decodingError(DecodingError)
    case etagError(Error)
    case internalError(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .httpError(let code): return "Non-2xx response: HTTP \(code)"
        case .emptyBody: return "Empty response body"
        case .decodingError(let error): return "Decoding failed: \(error.localizedDescription)"
        case .etagError(let error): return "Etag storage failed: \(error.localizedDescription)"
        case .internalError(let error): return "Internal error: \(error.localizedDescription)"
        }
    }
}
