/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// On-disk representation of a cached remote configuration.
///
/// The HTTP ETag, the propagation metadata, and the configuration payload itself are kept
/// together and written in a single atomic file, so metadata can never point at a
/// configuration version that was not durably cached (and vice versa).
internal struct RemoteConfigurationCache: Codable {
    /// Propagation metadata for a cached remote configuration, used to correlate configuration
    /// propagation telemetry with the CDN version that produced it.
    struct Metadata: Codable, Equatable {
        /// Value of the `x-amz-version-id` response header.
        let versionId: String?
        /// Parsed value of the `last-modified` response header.
        let lastModified: Date?
        /// Date this configuration was fetched and persisted.
        let lastSynced: Date?
        /// Identifier of the sync that produced this configuration version, generated the same
        /// way as the request IDs used for event uploads. Reused by every session running on
        /// this version, until the next genuine (non-304) sync.
        let syncId: String?
        /// Date this configuration version was first observed as applied. Stamped once and
        /// reused on every subsequent session that runs on the same version.
        let firstApplied: Date?
    }

    /// Value of the `etag` response header, sent back as `If-None-Match`.
    let etag: String?
    /// Propagation metadata for `configuration`, if it was successfully cached.
    let metadata: Metadata?
    /// The last successfully decoded and cached configuration payload.
    let configuration: RemoteConfiguration?
}

extension RemoteConfigurationCache.Metadata {
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
/// A successful fetch is persisted as `<id>.json` inside the supplied `directory`, as a single
/// `RemoteConfigurationCache` document combining the HTTP ETag, the propagation metadata used
/// for configuration telemetry, and the configuration payload. The ETag is sent back as
/// `If-None-Match` on subsequent requests, turning unchanged responses into lightweight 304s
/// that skip body transfer and re-parse entirely.
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
    ///     from the cache read below. `MessageBus` accumulates configuration telemetry and
    ///     flushes it once, 5 seconds after core initialization, to whichever receivers are
    ///     connected by then — reporting this early is safe as long as the consuming feature
    ///     (e.g. RUM) is enabled within that window, but telemetry sent before a receiver
    ///     connects is dropped if that window has already passed. A genuinely new fetch
    ///     (non-304) is only reported on a later launch's cache read, once it has been
    ///     applied. Read and fetch errors are also reported here.
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
            let cache = try JSONDecoder().decode(RemoteConfigurationCache.self, from: data)

            guard let configuration = cache.configuration else {
                return nil
            }

            report(cache: cache, to: telemetry)

            return configuration
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

        // Build request with conditional ETag header if a previous ETag is stored.
        var request = URLRequest(
            url: site.remoteConfigurationEndpoint
                .appendingPathComponent("v1")
                .appendingPathComponent(id)
                .appendingPathExtension("json")
        )

        var cache: RemoteConfigurationCache?
        if let file = try? directory.file(named: cacheFilename) {
            do {
                cache = try decoder.decode(RemoteConfigurationCache.self, from: file.read())
                cache?.etag.map { request.setValue($0, forHTTPHeaderField: "If-None-Match") }
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

                guard let data, !data.isEmpty else {
                    // Still update the ETag so a known-bad payload is not re-fetched on every
                    // sync; we recover once the server publishes an update. Previously cached
                    // configuration and metadata are left untouched.
                    self.updateETag(from: http, previous: cache, telemetry: telemetry)
                    throw RemoteConfigurationError.emptyBody
                }

                let remoteConfiguration: RemoteConfiguration
                do {
                    remoteConfiguration = try decoder.decode(RemoteConfiguration.self, from: data)
                } catch {
                    self.updateETag(from: http, previous: cache, telemetry: telemetry)
                    throw error
                }

                // All checks passed — persist configuration, metadata, and etag together in a
                // single atomic write (File.write uses .atomic: write to temp, then rename), so
                // a later `readCache()` never reports a version that was never actually written
                // to disk. If the write fails, the configuration is not durably cached, so it is
                // not delivered to `handler` either — the outer catch reports the failure and a
                // later sync will retry.
                try self.saveCache(remoteConfiguration, from: http)

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
    private func report(cache: RemoteConfigurationCache, to telemetry: Telemetry) {
        guard var metadata = cache.metadata else {
            return
        }

        if metadata.firstApplied == nil {
            metadata = RemoteConfigurationCache.Metadata(
                versionId: metadata.versionId,
                lastModified: metadata.lastModified,
                lastSynced: metadata.lastSynced,
                syncId: metadata.syncId,
                firstApplied: dateProvider.now
            )
            do {
                try write(
                    cache: RemoteConfigurationCache(etag: cache.etag, metadata: metadata, configuration: cache.configuration)
                )
            } catch {
                telemetry.error("[RemoteConfig] Failed to save remote configuration metadata", error: error)
            }
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
    }

    /// Builds and persists the cache from a genuine (non-304) fetch's HTTP response, once the
    /// fetched configuration has been successfully decoded. `syncId` and `lastSynced` mark this
    /// as a genuine sync, distinct from a 304. `firstApplied` is left unset: this version has
    /// not been applied yet, since a fetch that completes mid-session does not retroactively
    /// re-apply already initialized features.
    ///
    /// Throws if the write fails, so the caller can treat an undelivered, uncached configuration
    /// as a failed sync rather than deliver a configuration that was never durably persisted.
    private func saveCache(_ configuration: RemoteConfiguration, from response: HTTPURLResponse) throws {
        let etag = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "etag" })?.value as? String
        let versionId = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "x-amz-version-id" })?.value as? String
        let lastModifiedHeader = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "last-modified" })?.value as? String

        let cache = RemoteConfigurationCache(
            etag: etag,
            metadata: RemoteConfigurationCache.Metadata(
                versionId: versionId,
                lastModified: lastModifiedHeader.flatMap { RemoteConfigurationCache.Metadata.httpDateFormatter.date(from: $0) },
                lastSynced: dateProvider.now,
                syncId: UUID().uuidString,
                firstApplied: nil
            ),
            configuration: configuration
        )

        try write(cache: cache)
    }

    /// Persists only the response's `ETag`, leaving any previously cached configuration and
    /// metadata untouched.
    ///
    /// Called when the response body could not be cached or decoded, so the next sync sends
    /// `If-None-Match` for this same (still-broken) payload and short-circuits to a lightweight
    /// 304 instead of re-fetching and re-failing on every sync, without `report(cache:to:)`
    /// ever reporting this undelivered version as applied.
    private func updateETag(from response: HTTPURLResponse, previous: RemoteConfigurationCache?, telemetry: Telemetry) {
        let etag = response.allHeaderFields.first(where: { ($0.key as? String)?.lowercased() == "etag" })?.value as? String

        let cache = RemoteConfigurationCache(
            etag: etag,
            metadata: previous?.metadata,
            configuration: previous?.configuration
        )

        do {
            try write(cache: cache)
        } catch {
            telemetry.error("[RemoteConfig] Failed to save remote configuration metadata", error: error)
        }
    }

    /// Persists the cache to `<id>.json`.
    private func write(cache: RemoteConfigurationCache) throws {
        try write(JSONEncoder().encode(cache), to: "\(id).json")
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
