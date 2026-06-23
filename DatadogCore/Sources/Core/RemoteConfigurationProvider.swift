/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Fetches remote configuration when started and when the app enters foreground.
internal final class RemoteConfigurationProvider {
    let id: String
    let site: DatadogSite
    let directory: Directory
    let httpClient: HTTPClient
    private let notificationCenter: NotificationCenter
    private let dateProvider: DateProvider
    @ReadWriteLock
    private var lastSyncDate: Date? = nil
    private let minimumSyncInterval: TimeInterval = 300
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

    func start(_ completionHandler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
        // Synchronous read on the caller's thread (main thread during SDK init).
        // Acceptable because the file is small (a single JSON document) and only
        // present after a previous successful fetch — absent on first launch.
        if let cached = Self.readCache(id: id, from: directory) {
            completionHandler(cached)
        }

#if canImport(UIKit)
        foregroundObserver = notificationCenter.addObserver(
            forName: ApplicationNotifications.willEnterForeground,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }
            if let last = self.lastSyncDate,
               self.dateProvider.now.timeIntervalSince(last) < self.minimumSyncInterval {
                return
            }
            self.sync(completionHandler)
        }
#endif

        sync(completionHandler)
    }

    func stop() {
        _foregroundObserver.mutate { observer in
#if canImport(UIKit)
            observer.map { notificationCenter.removeObserver($0) }
#endif
            observer = nil
        }
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

    /// Fires an async CDN fetch and persists the configuration on success.
    private func sync(_ completionHandler: @escaping (Result<RemoteConfiguration, RemoteConfigurationError>) -> Void) {
        // Build request with conditional ETag header if a previous ETag is stored.
        var request = URLRequest(url: site.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent(id)
            .appendingPathExtension("json"))

        if directory.hasFile(named: "\(id).json"),
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
                // 1. Not Modified — existing persisted configuration is still valid.
                if http.statusCode == 304 {
                    self.lastSyncDate = self.dateProvider.now
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

                // All checks passed — persist to disk.
                // File.write uses .atomic (write to temp, then rename), so the update is
                // all-or-nothing: the existing file is never left in a truncated state.
                do {
                    try File(url: self.directory.url.appendingPathComponent("\(self.id).json")).write(data: data)
                    self.lastSyncDate = self.dateProvider.now
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
                    completionHandler(.success(remoteConfiguration))
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
