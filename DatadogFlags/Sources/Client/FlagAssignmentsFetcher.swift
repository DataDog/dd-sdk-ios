/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagAssignmentsFetching {
    var responseSigningMode: Flags.ResponseSigningMode { get }
    var responseSigningCacheScope: String? { get }
    func resolveResponseSigningCacheScope(_ completion: @escaping (String?) -> Void)
    func isVerified(_ proof: FlagsResponseVerification?, at now: Date) -> Bool
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    )
}

internal extension FlagAssignmentsFetching {
    var responseSigningMode: Flags.ResponseSigningMode { .off }
    var responseSigningCacheScope: String? { nil }
    func resolveResponseSigningCacheScope(_ completion: @escaping (String?) -> Void) {
        completion(responseSigningCacheScope)
    }
    func isVerified(_ proof: FlagsResponseVerification?, at now: Date) -> Bool { false }
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?

    private let featureScope: any FeatureScope
    private let assignmentFetchQueue: DispatchQueue
    private let fetch: (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void

    private let verifier: FlagsResponseVerifier?
    private let dateProvider: any DateProvider
    private let signingFetch: ((URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void)?
    private var reportedSigningOutcomes = Set<String>()
    private struct SigningLifecycleState {
        var cacheScope: String?
        var stopped = false
    }
    @ReadWriteLock
    private var signingState = SigningLifecycleState()
    private static let decoder = JSONDecoder()

    var responseSigningMode: Flags.ResponseSigningMode { verifier?.configuration.mode ?? .off }

    var responseSigningCacheScope: String? { signingState.cacheScope }

    private var hasStoppedSigning: Bool { verifier != nil && signingState.stopped }

    /// Permanent for this feature instance. A late core-context message must never reactivate it.
    func invalidateResponseSigningLifetime() {
        guard verifier != nil else {
            return
        }
        _signingState.mutate { state in
            state.stopped = true
            state.cacheScope = nil
        }
    }

    /// Called on the core context bus before queued network work. Completion cannot restore an older scope.
    @discardableResult
    func updateResponseSigningCacheScope(_ context: DatadogContext) -> String? {
        guard let verifier, !signingState.stopped else {
            return nil
        }
        let request = try? URLRequest.flagAssignmentsRequest(
            url: url(with: context),
            evaluationContext: .empty,
            context: context,
            customHeaders: customHeaders
        )
        let scope = request.map {
            verifier.cacheScope(
                request: $0,
                environment: context.env,
                customHeaderNames: customHeaders.map { Array($0.keys) } ?? []
            )
        }
        var activeScope: String?
        _signingState.mutate { state in
            guard !state.stopped else {
                return
            }
            state.cacheScope = scope
            activeScope = scope
        }
        return activeScope
    }

    func resolveResponseSigningCacheScope(_ completion: @escaping (String?) -> Void) {
        guard !hasStoppedSigning else {
            completion(nil)
            return
        }
        featureScope.context { [weak self] context in
            completion(self?.updateResponseSigningCacheScope(context))
        }
    }

    func isVerified(_ proof: FlagsResponseVerification?, at now: Date) -> Bool {
        guard let verifier else {
            return false
        }
        guard let current = responseSigningCacheScope, proof?.cacheScope == current else {
            return false
        }
        return proof?.isValid(at: now, scope: verifier.scope) == true
    }

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        responseSigning: Flags.ResponseSigningConfiguration = .init()
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let delegate = responseSigning.mode == .off ? nil : FlagsSigningRedirectDelegate()
        let urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            responseSigning: responseSigning,
            signingFetch: urlSession.fetchSigning,
            fetch: urlSession.fetch
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        assignmentFetchQueue: DispatchQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-flags-assignment-fetch",
            qos: .utility,
            autoreleaseFrequency: .workItem
        ),
        responseSigning: Flags.ResponseSigningConfiguration = .init(),
        dateProvider: any DateProvider = SystemDateProvider(),
        signingFetch: ((URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void)? = nil,
        fetch: @escaping (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.assignmentFetchQueue = assignmentFetchQueue
        self.fetch = fetch
        self.dateProvider = dateProvider
        self.verifier = responseSigning.mode == .off ? nil : FlagsResponseVerifier(configuration: responseSigning)
        self.signingFetch = signingFetch
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        // Repository callbacks can invoke application code; keep them off shared SDK work queues.
        let completion: (Result<FlagAssignmentsResponse, FlagsError>) -> Void = { result in
            DispatchQueue.global(qos: .utility).async {
                completion(result)
            }
        }
        guard !hasStoppedSigning else {
            completion(.failure(.clientNotInitialized))
            return
        }
        featureScope.context { [weak self] context in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            let cacheScope = self.updateResponseSigningCacheScope(context)
            self.assignmentFetchQueue.async {
                self.fetchAssignments(
                    for: evaluationContext,
                    context: context,
                    cacheScope: cacheScope,
                    completion: completion
                )
            }
        }
    }

    private func fetchAssignments(
        for evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        cacheScope: String?,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        guard !hasStoppedSigning else {
            completion(.failure(.clientNotInitialized))
            return
        }
        do {
            let request = try URLRequest.flagAssignmentsRequest(
                url: url(with: context),
                evaluationContext: evaluationContext,
                context: context,
                customHeaders: customHeaders
            )
            if let verifier {
                fetchSigned(
                    request,
                    verifier: verifier,
                    cacheScope: cacheScope,
                    supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                    completion: completion
                )
                return
            }
            fetch(request) { [assignmentFetchQueue, featureScope] result in
                assignmentFetchQueue.async {
                    Self.handleFetchResult(
                        result,
                        supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                        featureScope: featureScope,
                        completion: completion
                    )
                }
            }
        } catch let error {
            DD.logger.error("Failed to encode flag assignments request body.", error: error)
            featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
            completion(.failure(.invalidConfiguration))
        }
    }

    private func fetchSigned(
        _ request: URLRequest,
        verifier: FlagsResponseVerifier,
        cacheScope: String?,
        supportsObfuscation: Bool,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        let prepared: URLRequest?
        do { prepared = try verifier.prepare(request) } catch {
            reportSigning(error as? FlagsSigningError ?? .invalidProof)
            guard responseSigningMode == .observe else {
                completion(.failure(.invalidConfiguration))
                return
            }
            prepared = nil
        }
        guard let signingFetch else {
            completion(.failure(.invalidConfiguration))
            return
        }
        let effective = prepared ?? request
        guard !hasStoppedSigning else {
            completion(.failure(.clientNotInitialized))
            return
        }
        signingFetch(effective) { [weak self] result in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            self.assignmentFetchQueue.async {
                guard !self.hasStoppedSigning else {
                    completion(.failure(.clientNotInitialized))
                    return
                }
                switch result {
                case .failure(let error):
                    Self.handleFetchResult(
                        .failure(error),
                        supportsObfuscation: supportsObfuscation,
                        featureScope: self.featureScope,
                        completion: completion
                    )
                case .success(let (data, response)):
                    // Redirect failures are transport failures, never optional verification failures.
                    guard response.url == effective.url, (200..<300).contains(response.statusCode) else {
                        completion(.failure(.networkError(URLError(.badServerResponse))))
                        return
                    }
                    var proof: FlagsResponseVerification?
                    if let prepared {
                        do {
                            proof = try verifier.verify(
                                request: prepared,
                                response: response,
                                body: data,
                                now: self.dateProvider.now
                            )
                            proof?.cacheScope = cacheScope
                            self.reportSigning(nil)
                        } catch {
                            self.reportSigning(error as? FlagsSigningError ?? .invalidProof)
                            guard self.responseSigningMode == .observe else {
                                completion(.failure(.invalidResponse))
                                return
                            }
                        }
                    }
                    Self.handleFetchResult(
                        .success(data),
                        supportsObfuscation: supportsObfuscation,
                        featureScope: self.featureScope,
                        verification: proof,
                        cacheScope: cacheScope,
                        completion: completion
                    )
                }
            }
        }
    }

    private func reportSigning(_ error: FlagsSigningError?) {
        let outcome = error?.rawValue ?? "verified"
        guard reportedSigningOutcomes.insert(outcome).inserted else {
            return
        }
        featureScope.telemetry.debug("Flags response signing", attributes: ["outcome": outcome])
    }

    private static func handleFetchResult(
        _ result: Result<Data, Error>,
        supportsObfuscation: Bool,
        featureScope: any FeatureScope,
        verification: FlagsResponseVerification? = nil,
        cacheScope: String? = nil,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        switch result {
        case .success(let data):
            do {
                var response = try decoder.decode(FlagAssignmentsResponse.self, from: data)
                response.verification = verification
                response.responseSigningCacheScope = cacheScope
                guard response.obfuscation == nil || supportsObfuscation else {
                    throw FlagsError.invalidResponse
                }

                // Log any flags that failed to decode to telemetry
                if !response.failedFlags.isEmpty {
                    for (flagKey, errorDescription) in response.failedFlags {
                        let error = InternalError(description: errorDescription)
                        DD.logger.warn(
                            "Failed to decode flag '\(flagKey)' from flag assignments response. Flag will be dropped from configuration.",
                            error: error
                        )
                        featureScope.telemetry.debug(
                            "Failed to decode flag '\(flagKey)' from flag assignments response",
                            attributes: [
                                "flagKey": flagKey,
                                "errorDescription": errorDescription
                            ]
                        )
                    }
                }

                completion(.success(response))
            } catch {
                featureScope.telemetry.error(
                    "Failed to decode \(FlagAssignmentsResponse.self) from flag assignments response",
                    error: error
                )
                completion(.failure(.invalidResponse))
            }
        case .failure(let error):
            DD.logger.error("Failed to fetch flag assignments from the server.", error: error)
            featureScope.telemetry.error("Failed to fetch flag assignments from the server", error: error)
            completion(.failure(.networkError(error)))
        }
    }

    private func url(with context: DatadogContext) -> URL {
        customEndpoint ?? context.site.flagsEndpoint().appendingPathComponent("precompute-assignments")
    }
}

extension DatadogSite {
    internal func flagsEndpoint(subdomain: String = "preview") -> URL {
        switch self {
        // swiftlint:disable force_unwrapping
        case .us1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        case .us3: return URL(string: "https://\(subdomain).ff-cdn.us3.datadoghq.com")!
        case .us5: return URL(string: "https://\(subdomain).ff-cdn.us5.datadoghq.com")!
        case .eu1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.eu")!
        case .ap1: return URL(string: "https://\(subdomain).ff-cdn.ap1.datadoghq.com")!
        case .ap2: return URL(string: "https://\(subdomain).ff-cdn.ap2.datadoghq.com")!
        case .uk1: return URL(string: "https://\(subdomain).ff-cdn.uk1.datadoghq.com")!
        case .us1_fed, .us2_fed:
            DD.logger.warn(
                """
                Government sites (us1_fed, us2_fed) are not officially supported for feature flags. \
                Falling back to us1 endpoint.
                """
            )
            return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        // swiftlint:enable force_unwrapping
        }
    }
}

extension URLSession {
    fileprivate func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let task = self.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            completion(.success(data))
        }
        task.resume()
    }
}

/// Return the redirect response without following it; the ordinary HTTP check rejects it.
private final class FlagsSigningRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension URLSession {
    func fetchSigning(_ request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        let task = dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode)
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            completion(.success((data, response)))
        }
        task.resume()
    }
}

/// Core sends updated app/identity context before later work on its message bus.
internal struct FlagsSigningScopeReceiver: FeatureMessageReceiver {
    let fetcher: FlagAssignmentsFetcher

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case .context(let context) = message else {
            return false
        }
        fetcher.updateResponseSigningCacheScope(context)
        return true
    }
}

/// Owned only by FlagsFeature, never by the retained fetcher, client, repository or message receiver.
/// Core.stop releases its features; this marker closes signing even if a client retains the fetcher.
internal final class FlagsSigningLifetime {
    private let fetcher: FlagAssignmentsFetcher

    init(fetcher: FlagAssignmentsFetcher) {
        self.fetcher = fetcher
    }

    deinit {
        fetcher.invalidateResponseSigningLifetime()
    }
}
