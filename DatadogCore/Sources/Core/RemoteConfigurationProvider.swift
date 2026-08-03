/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// CDN response metadata for a remote configuration fetch, used to correlate
/// configuration propagation telemetry with the CDN version that produced it.
internal struct RemoteConfigurationMetadata: Codable, Equatable {
    /// Value of the `etag` response header, sent back as `If-None-Match`.
    let etag: String?
    /// Value of the `x-amz-version-id` response header.
    let versionId: String?
    /// Parsed value of the `last-modified` response header.
    let lastModified: Date?
    /// Date this configuration was fetched and persisted.
    let lastSynced: Date?
    /// Identifier of the sync that produced this configuration version, generated the same way
    /// as the request IDs used for event uploads. Reused by every session running on this
    /// version, until the next genuine (non-304) sync.
    let syncId: String?
    /// Date this configuration version was first observed as applied. Stamped once and reused
    /// on every subsequent session that runs on the same version.
    let firstApplied: Date?
}

extension RemoteConfigurationMetadata {
    /// Formats and parses the `last-modified` response header (RFC 7231 IMF-fixdate,
    /// e.g. `Wed, 21 Oct 2015 07:28:00 GMT`).
    static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

/// Fetches and caches remote configuration from the Datadog CDN.
///
/// On `start(_:)`, the provider immediately delivers any previously cached configuration
/// from disk, then fires an async CDN request to refresh it. On UIKit platforms it also
/// re-syncs whenever the app returns to the foreground, so long-lived sessions always
/// converge on the latest configuration without requiring a restart.
///
/// ## Caching
/// A successful fetch is persisted as `<id>.json` inside the supplied `directory`.
/// The accompanying HTTP ETag, and the `x-amz-version-id` / `last-modified` headers
/// used for propagation telemetry, are stored in `<id>.metadata.json`. The ETag is sent
/// back as `If-None-Match` on subsequent requests, turning unchanged responses into
/// lightweight 304s that skip body transfer and re-parse entirely.
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
    /// - Parameters:
    ///   - handler: Called with the configuration whenever one is available (from cache or
    ///     network). Read or fetch errors are not surfaced here; they are reported to
    ///     `telemetry` instead.
    ///   - telemetry: Reports the propagation of the configuration version delivered from
    ///     cache (if any) on the once-per-session configuration telemetry, synchronously
    ///     from the cache read below. Configuration telemetry buffers sends made before a
    ///     receiver is registered for the session, so reporting this early is safe. A
    ///     genuinely new fetch (non-304) only updates the persisted metadata; it does not
    ///     report telemetry on its own, since the fetched version does not take effect
    ///     until the next application launch. Read and fetch errors are also reported here.
    func start(
        _ handler: @escaping (RemoteConfiguration) -> Void,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        readCache(telemetry: telemetry).map(handler)

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
            self.sync(handler, telemetry: telemetry)
        }
#endif

        sync(handler, telemetry: telemetry)
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

    private func readCache(telemetry: Telemetry) -> RemoteConfiguration? {
        let cacheFilename = "\(id).json"
        guard directory.hasFile(named: cacheFilename) else {
            return nil
        }

        do {
            let data = try directory.file(named: cacheFilename).read()
            let remoteConfiguration = try JSONDecoder().decode(RemoteConfiguration.self, from: data)
            reportMetadata(to: telemetry)
            return remoteConfiguration
        } catch {
            telemetry.error("[RemoteConfig] Failed to read cached remote configuration", error: error)
            return nil
        }
    }

    /// Fires an async CDN fetch and persists the configuration on success.
    private func sync(
        _ handler: @escaping (RemoteConfiguration) -> Void,
        telemetry: Telemetry
    ) {
        let decoder = JSONDecoder()
        let cacheFilename = "\(id).json"
        let metadataFilename = "\(id).metadata.json"

        // Build request with conditional ETag header if a previous ETag is stored.
        var request = URLRequest(
            url: site.remoteConfigurationEndpoint
                .appendingPathComponent("v1")
                .appendingPathComponent(id)
                .appendingPathExtension("json")
        )

        if let file = try? directory.file(named: metadataFilename) {
            do {
                let metadata = try decoder.decode(RemoteConfigurationMetadata.self, from: file.read())
                metadata.etag.map { request.setValue($0, forHTTPHeaderField: "If-None-Match") }
            } catch {
                telemetry.error("[RemoteConfig] Failed to read cached metadata etag", error: error)
            }
        }

        httpClient.send(request: request, delegate: nil) { [weak self] result in
            guard let self else {
                return
            }

            do {
                let (http, data) = try result.get()

                if http.statusCode == 304 {
                    self.lastSyncDate = self.dateProvider.now
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    throw RemoteConfigurationError.httpError(http.statusCode)
                }

                // Persist metadata before decoding — it belongs to the HTTP response,
                // not to whether we could parse the body. This prevents re-fetching a
                // known-bad payload on every sync; we recover when the server updates.
                self.saveMetadata(from: http, telemetry: telemetry)

                guard let data, !data.isEmpty else {
                    throw RemoteConfigurationError.emptyBody
                }

                let remoteConfiguration = try decoder.decode(RemoteConfiguration.self, from: data)

                // All checks passed — persist to disk.
                // File.write uses .atomic (write to temp, then rename), so the update is
                // all-or-nothing: the existing file is never left in a truncated state.
                try self.write(data, to: cacheFilename)
                self.lastSyncDate = self.dateProvider.now

                handler(remoteConfiguration)
            } catch {
                telemetry.error("[RemoteConfig] Failed to sync remote configuration", error: error)
            }
        }
    }

    /// Reports the configuration version applied from cache on the once-per-session
    /// configuration telemetry. Stamps `firstApplied` the first time this version is
    /// observed as applied, and persists it back to disk so every later session running
    /// on the same version reports the same value.
    private func reportMetadata(to telemetry: Telemetry) {
        guard let file = try? directory.file(named: "\(id).metadata.json") else {
            return
        }

        do {
            var metadata = try JSONDecoder().decode(RemoteConfigurationMetadata.self, from: file.read())

            if metadata.firstApplied == nil {
                metadata = RemoteConfigurationMetadata(
                    etag: metadata.etag,
                    versionId: metadata.versionId,
                    lastModified: metadata.lastModified,
                    lastSynced: metadata.lastSynced,
                    syncId: metadata.syncId,
                    firstApplied: dateProvider.now
                )
                try write(metadata: metadata)
            }

            telemetry.configuration(
                remoteConfiguration: .init(
                    configId: id,
                    versionId: metadata.versionId,
                    lastModified: metadata.lastModified,
                    lastSynced: metadata.lastSynced,
                    firstApplied: metadata.firstApplied,
                    syncId: metadata.syncId
                )
            )
        } catch {
            telemetry.error("[RemoteConfig] Failed to report applied remote configuration", error: error)
        }
    }

    /// Builds and persists metadata from a genuine (non-304) fetch's HTTP response.
    /// `syncId` and `lastSynced` mark this as a genuine sync, distinct from a 304.
    /// `firstApplied` is left unset: this version has not been applied yet, since a
    /// fetch that completes mid-session does not retroactively re-apply already
    /// initialized features.
    private func saveMetadata(from response: HTTPURLResponse, telemetry: Telemetry) {
        let etag = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "etag" })?.value as? String
        let versionId = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "x-amz-version-id" })?.value as? String
        let lastModifiedHeader = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "last-modified" })?.value as? String

        let metadata = RemoteConfigurationMetadata(
            etag: etag,
            versionId: versionId,
            lastModified: lastModifiedHeader.flatMap { RemoteConfigurationMetadata.httpDateFormatter.date(from: $0) },
            lastSynced: dateProvider.now,
            syncId: UUID().uuidString,
            firstApplied: nil
        )

        do {
            try write(metadata: metadata)
        } catch {
            telemetry.error("[RemoteConfig] Failed to save remote configuration metadata", error: error)
        }
    }

    /// Persists metadata to `<id>.metadata.json`.
    private func write(metadata: RemoteConfigurationMetadata) throws {
        try write(JSONEncoder().encode(metadata), to: "\(id).metadata.json")
    }

    private func write(_ data: Data, to filename: String) throws {
        let file = directory.hasFile(named: filename)
            ? try directory.file(named: filename)
            : try directory.createFile(named: filename)
        try file.write(data: data)
    }
}

internal enum RemoteConfigurationError: Error, LocalizedError {
    case httpError(Int)
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Non-2xx response: HTTP \(code)"
        case .emptyBody: return "Empty response body"
        }
    }
}
