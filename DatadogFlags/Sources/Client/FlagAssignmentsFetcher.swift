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
    /// Like `isVerified`, but in `required` mode an expired proof stays usable unless `expireVerifiedFlags` is set.
    func isTrusted(_ proof: FlagsResponseVerification?, at now: Date) -> Bool
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
        assignmentToken: String?,
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
    func isTrusted(_ proof: FlagsResponseVerification?, at now: Date) -> Bool { isVerified(proof, at: now) }
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        flagAssignments(
            for: evaluationContext,
            experimentationOptOut: nil,
            diagnostics: nil,
            assignmentToken: nil,
            completion: completion
        )
    }
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?
    let flagSelection: CanonicalFlagSelection?

    private let featureScope: any FeatureScope
    private let assignmentFetchQueue: DispatchQueue
    private let fetch: (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void

    private static let flagSelectionIgnoredHeader = "DD-Flag-Selection-Ignored"
    // The reasons the server sends in `DD-Flag-Selection-Ignored`. Any other value, for example one set by a proxy
    // behind `customFlagsEndpoint`, is reported as `unknown`, so header content never reaches logs or telemetry.
    private static let flagSelectionIgnoredReasons = [
        "malformed_selection", "too_many_values", "invalid_key_pattern", "invalid_tag", "tag_load_failed"
    ]
    private static let unknownFlagSelectionIgnoredReason = "unknown"
    private static let redactedFlagSelectionIgnoredReason = "redacted"
    // The longest known reason is 19 bytes, so a longer value is reported as `unknown` without a lookup.
    private static let maxFlagSelectionIgnoredReasonBytes = 32

    private let verifier: FlagsResponseVerifier?
    private let dateProvider: any DateProvider
    private let signingFetch: ((URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void)?
    private var reportedSigningOutcomes = Set<String>()
    /// The only context values that the signing scope reads. RUM and other context changes do not change them.
    private struct ScopeInputs: Equatable {
        let site: DatadogSite
        let env: String
        let clientToken: String
        let source: String
    }
    private struct SigningLifecycleState {
        var cacheScope: String?
        var scopeInputs: ScopeInputs?
        var stopped = false
        var sessionInvalidated = false
    }
    /// Invalidated when the feature lifetime ends, so it releases its delegate.
    private let signingSession: URLSession?
    @ReadWriteLock
    private var signingState = SigningLifecycleState()

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
            state.scopeInputs = nil
            state.sessionInvalidated = signingSession != nil
        }
        signingSession?.finishTasksAndInvalidate()
    }

    /// For tests: the signing session that the feature lifetime invalidates.
    var responseSigningSession: URLSession? { signingSession }
    var hasInvalidatedSigningSession: Bool { signingState.sessionInvalidated }

    /// Called on the core context bus before queued network work. Completion cannot restore an older scope.
    @discardableResult
    func updateResponseSigningCacheScope(_ context: DatadogContext) -> String? {
        guard let verifier, !signingState.stopped else {
            return nil
        }
        let inputs = ScopeInputs(site: context.site, env: context.env, clientToken: context.clientToken, source: context.source)
        // Core sends a context message for each context write. Skip the work when no scope input changed.
        let current = signingState
        if current.scopeInputs == inputs, let scope = current.cacheScope {
            return scope
        }
        let request = try? URLRequest.flagAssignmentsRequest(
            url: url(with: context),
            evaluationContext: .empty,
            context: context,
            customHeaders: customEndpoint != nil ? customHeaders : nil,
            flagSelection: flagSelection
        )
        let scope = request.map {
            verifier.cacheScope(
                request: $0,
                environment: context.env,
                customHeaderNames: customEndpoint != nil ? customHeaders.map { Array($0.keys) } ?? [] : [],
                flagSelection: flagSelection
            )
        }
        var activeScope: String?
        _signingState.mutate { state in
            guard !state.stopped else {
                return
            }
            state.cacheScope = scope
            state.scopeInputs = scope == nil ? nil : inputs
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

    func isTrusted(_ proof: FlagsResponseVerification?, at now: Date) -> Bool {
        guard let verifier else {
            return false
        }
        guard let current = responseSigningCacheScope, proof?.cacheScope == current else {
            return false
        }
        // `expireVerifiedFlags` is a required-mode setting. Observe never trusts an expired proof.
        let allowExpired = verifier.configuration.mode == .required && !verifier.configuration.expireVerifiedFlags
        return proof?.isValid(at: now, scope: verifier.scope, allowExpired: allowExpired) == true
    }

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
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
            flagSelection: flagSelection,
            featureScope: featureScope,
            responseSigning: responseSigning,
            signingSession: responseSigning.mode == .off ? nil : urlSession,
            signingFetch: urlSession.fetchSigning,
            fetch: urlSession.fetch
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
        featureScope: any FeatureScope,
        assignmentFetchQueue: DispatchQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-flags-assignment-fetch",
            qos: .utility,
            autoreleaseFrequency: .workItem
        ),
        responseSigning: Flags.ResponseSigningConfiguration = .init(),
        dateProvider: any DateProvider = SystemDateProvider(),
        minimumNotBeforeStore: (any FlagsMinimumNotBeforeStore)? = nil,
        signingSession: URLSession? = nil,
        signingFetch: ((URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void)? = nil,
        fetch: @escaping (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.flagSelection = flagSelection
        self.featureScope = featureScope
        self.assignmentFetchQueue = assignmentFetchQueue
        self.fetch = fetch
        self.dateProvider = dateProvider
        self.verifier = responseSigning.mode == .off
            ? nil
            : FlagsResponseVerifier(
                configuration: responseSigning,
                minimumNotBeforeStore: minimumNotBeforeStore ?? DataStoreMinimumNotBeforeStore(dataStore: featureScope.dataStore)
            )
        self.signingSession = signingSession
        self.signingFetch = signingFetch
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot? = nil,
        assignmentToken: String? = nil,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        let authorization = evaluationContext.extractingAssignmentAuthorization()
        let evaluationContext = authorization.context
        let suppliedToken = assignmentToken ?? authorization.token
        let assignmentToken = AssignmentAuthorization.usableToken(suppliedToken)
        if authorization.shouldWarn || (suppliedToken?.isEmpty == false && assignmentToken == nil) {
            DD.logger.warn(AssignmentAuthorization.unusableTokenWarning)
        }
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
                    experimentationOptOut: experimentationOptOut,
                    diagnostics: diagnostics,
                    assignmentToken: assignmentToken,
                    context: context,
                    cacheScope: cacheScope,
                    completion: completion
                )
            }
        }
    }

    private func fetchAssignments(
        for evaluationContext: FlagsEvaluationContext,
        experimentationOptOut: ExperimentationOptOut?,
        diagnostics: FlagsRequestDiagnostics.Snapshot?,
        assignmentToken: String?,
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
                // Custom headers can carry proxy credentials, so only the custom endpoint receives them.
                customHeaders: customEndpoint != nil ? customHeaders : nil,
                flagSelection: flagSelection,
                experimentationOptOut: experimentationOptOut,
                diagnostics: diagnostics,
                assignmentToken: assignmentToken
            )
            if let verifier {
                fetchSigned(
                    request,
                    verifier: verifier,
                    experimentationOptOut: experimentationOptOut,
                    cacheScope: cacheScope,
                    supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                    requestCarriedAssignmentToken: assignmentToken != nil,
                    telemetry: SigningTelemetryContext(sdkVersion: context.sdkVersion, site: Self.signingSite(request.url)),
                    completion: completion
                )
                return
            }
            fetch(request) { [assignmentFetchQueue, featureScope, flagSelection] result in
                assignmentFetchQueue.async {
                    Self.handleFetchResult(
                        result,
                        experimentationOptOut: experimentationOptOut,
                        supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                        requestCarriedFlagSelection: flagSelection != nil,
                        requestCarriedAssignmentToken: assignmentToken != nil,
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
        experimentationOptOut: ExperimentationOptOut?,
        cacheScope: String?,
        supportsObfuscation: Bool,
        requestCarriedAssignmentToken: Bool,
        telemetry: SigningTelemetryContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        let prepared: URLRequest?
        do { prepared = try verifier.prepare(request) } catch {
            let reason = error as? FlagsSigningError ?? .unsupportedRequest
            reportSigning(reason, telemetry: telemetry)
            guard responseSigningMode == .observe else {
                completion(.failure(.responseSigningFailed(reason: reason.rawValue)))
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
                        experimentationOptOut: experimentationOptOut,
                        supportsObfuscation: supportsObfuscation,
                        requestCarriedFlagSelection: self.flagSelection != nil,
                        requestCarriedAssignmentToken: requestCarriedAssignmentToken,
                        featureScope: self.featureScope,
                        completion: completion
                    )
                case .success(let (data, response)):
                    // Redirect failures are transport failures, never optional verification failures.
                    guard response.url == effective.url else {
                        completion(.failure(.networkError(URLError(.badServerResponse))))
                        return
                    }
                    // An error status carries no assignments, so it is not verified. The shared handler maps it,
                    // for example to `assignmentAuthorizationFailed`, and never returns assignments for it.
                    guard (200..<300).contains(response.statusCode) else {
                        Self.handleFetchResult(
                            .success((data, response)),
                            experimentationOptOut: experimentationOptOut,
                            supportsObfuscation: supportsObfuscation,
                            requestCarriedFlagSelection: self.flagSelection != nil,
                            requestCarriedAssignmentToken: requestCarriedAssignmentToken,
                            featureScope: self.featureScope,
                            completion: completion
                        )
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
                            self.reportSigning(nil, telemetry: telemetry)
                            if proof?.ignoredMinimumNotBefore == true {
                                // Not a failure, so it is not a signing telemetry reason.
                                DD.logger.debug("Flag response signing: minimum-not-before-ignored.")
                            }
                        } catch {
                            let reason = error as? FlagsSigningError ?? .invalidProof
                            self.reportSigning(reason, telemetry: telemetry)
                            guard self.responseSigningMode == .observe else {
                                completion(.failure(.responseSigningFailed(reason: reason.rawValue)))
                                return
                            }
                        }
                    }
                    Self.handleFetchResult(
                        .success((data, response)),
                        experimentationOptOut: experimentationOptOut,
                        supportsObfuscation: supportsObfuscation,
                        requestCarriedFlagSelection: self.flagSelection != nil,
                        requestCarriedAssignmentToken: requestCarriedAssignmentToken,
                        featureScope: self.featureScope,
                        verification: proof,
                        cacheScope: cacheScope,
                        completion: completion
                    )
                }
            }
        }
    }

    /// The SDK version and the Datadog site of a signed request, for signing telemetry.
    struct SigningTelemetryContext {
        let sdkVersion: String
        let site: String
    }

    /// The Datadog site of a flags endpoint, for example `datad0g.com`. Other hosts report `custom`,
    /// so telemetry never carries a URL.
    static func signingSite(_ url: URL?) -> String {
        let host = url?.host?.lowercased() ?? ""
        let prefix = "preview.ff-cdn."
        guard host.hasPrefix(prefix) else {
            return "custom"
        }
        let site = String(host.dropFirst(prefix.count))
        // Match whole DNS labels, so `evildatadoghq.com` reports `custom`.
        let exact: Set<String> = ["datad0g.com", "datadoghq.com", "datadoghq.eu"]
        let isDatadog = exact.contains(site) || site.hasSuffix(".datadoghq.com") || site.hasSuffix(".datadoghq.eu")
        return isDatadog ? site : "custom"
    }

    private func reportSigning(_ error: FlagsSigningError?, telemetry: SigningTelemetryContext) {
        if let error, reportedSigningOutcomes.insert(error.rawValue).inserted {
            // One user log for each code. `required` fails closed, so it logs an error; `observe` only warns.
            if responseSigningMode == .required {
                DD.logger.error(error.logMessage)
            } else {
                DD.logger.warn(error.logMessage + " Flags are not verified.")
            }
        }
        let mode: String
        switch responseSigningMode {
        case .off: return
        case .observe: mode = "observe"
        case .required: mode = "required"
        }
        // `required` reports failures only. `observe` reports every result.
        if responseSigningMode == .required && error == nil {
            return
        }
        let result = error == nil ? "verified" : "unverified"
        // The event id carries (mode, result, reason). RUM telemetry deduplicates by id for each session and
        // samples the events, so the SDK keeps no dedupe set of its own: a sampled-out event can be sent again.
        let key = "\(mode):\(result):\(error?.rawValue ?? "")"
        var attributes: [String: Encodable] = [
            "mode": mode,
            "result": result,
            "sdk_version": telemetry.sdkVersion,
            "site": telemetry.site
        ]
        if let error {
            attributes["reason"] = error.rawValue
        }
        featureScope.telemetry.debug(id: "flags.response_signing:" + key, message: "flags.response_signing", attributes: attributes)
    }

    /// Returns the reason to report for a `DD-Flag-Selection-Ignored` value, or `nil` when the header is absent or empty.
    /// Values are compared on bytes, case-sensitively and without trimming.
    private static func reportedFlagSelectionIgnoredReason(_ value: String?, redact: Bool) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        guard !redact else {
            return redactedFlagSelectionIgnoredReason
        }
        guard value.utf8.count <= maxFlagSelectionIgnoredReasonBytes,
              let reason = flagSelectionIgnoredReasons.first(where: { $0.utf8.elementsEqual(value.utf8) }) else {
            return unknownFlagSelectionIgnoredReason
        }
        return reason
    }

    private static func handleFetchResult(
        _ result: Result<(Data, HTTPURLResponse), Error>,
        experimentationOptOut: ExperimentationOptOut?,
        supportsObfuscation: Bool,
        requestCarriedFlagSelection: Bool,
        requestCarriedAssignmentToken: Bool,
        featureScope: any FeatureScope,
        verification: FlagsResponseVerification? = nil,
        cacheScope: String? = nil,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        switch result {
        case let .success((data, httpResponse)):
            let ignoredReason = requestCarriedFlagSelection
                ? reportedFlagSelectionIgnoredReason(
                    httpResponse.value(forHTTPHeaderField: flagSelectionIgnoredHeader),
                    redact: requestCarriedAssignmentToken
                )
                : nil
            if httpResponse.statusCode == 401, isAssignmentAuthorizationRejection(data) {
                DD.logger.warn("Assignment download failed: \(AssignmentAuthorization.rejectionCode)")
                completion(.failure(.assignmentAuthorizationFailed))
                return
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                let error = URLError(.badServerResponse)
                if requestCarriedAssignmentToken {
                    DD.logger.warn("Failed to fetch flag assignments from the server.")
                } else {
                    DD.logger.warn("Failed to fetch flag assignments from the server.", error: error)
                }
                completion(.failure(.networkError(error)))
                return
            }
            do {
                var response = try FlagsNumericJSON.decode(FlagAssignmentsResponse.self, from: data).addingKeySpellings(from: data)
                response.verification = verification
                response.responseSigningCacheScope = cacheScope
                guard response.obfuscation == nil || supportsObfuscation else {
                    throw FlagsError.invalidResponse
                }

                guard ExperimentationOptOut.accepts(response, for: experimentationOptOut) else {
                    throw FlagsError.invalidResponse
                }

                // Report an ignored selection only once the full configuration is accepted.
                if let ignoredReason {
                    DD.logger.error("`Flags.Configuration.flagSelection` was ignored by the server (\(ignoredReason)). Loaded the full flag configuration.")
                    // One id per reason: telemetry drops a repeated id within a session, so a shared id would hide later reasons.
                    featureScope.telemetry.debug(
                        id: "flags:selection-ignored:\(ignoredReason)",
                        message: "Flag selection ignored",
                        attributes: ["reason": ignoredReason]
                    )
                }

                // Log any flags that failed to decode to telemetry
                if !response.failedFlags.isEmpty {
                    for (flagKey, errorDescription) in response.failedFlags {
                        if requestCarriedAssignmentToken {
                            // Do not reflect server-controlled response details when a credential was sent.
                            let message = "Failed to decode a flag from flag assignments response"
                            DD.logger.warn("\(message). Flag will be dropped from configuration.")
                            featureScope.telemetry.debug(message)
                        } else {
                            let message = "Failed to decode flag '\(flagKey)' from flag assignments response"
                            let error = InternalError(description: errorDescription)
                            DD.logger.warn("\(message). Flag will be dropped from configuration.", error: error)
                            featureScope.telemetry.debug(
                                message,
                                attributes: ["flagKey": flagKey, "errorDescription": errorDescription]
                            )
                        }
                    }
                }

                completion(.success(response))
            } catch {
                let message = "Failed to decode \(FlagAssignmentsResponse.self) from flag assignments response"
                if requestCarriedAssignmentToken {
                    DD.logger.error(message)
                    featureScope.telemetry.error(message)
                } else {
                    featureScope.telemetry.error(message, error: error)
                }
                completion(.failure(.invalidResponse))
            }
        case .failure(let error):
            // The repository handles fetch failures through its error or stale state.
            if requestCarriedAssignmentToken {
                DD.logger.warn("Failed to fetch flag assignments from the server.")
                completion(.failure(.networkError(sanitizedTransportError(error))))
            } else {
                DD.logger.warn("Failed to fetch flag assignments from the server.", error: error)
                completion(.failure(.networkError(error)))
            }
        }
    }

    private static func isAssignmentAuthorizationRejection(_ data: Data) -> Bool {
        guard let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let errors = document["errors"] as? [Any] else {
            return false
        }
        // An unrelated or malformed sibling must not hide a typed rejection.
        return errors.contains { error in
            (error as? [String: Any])?["code"] as? String == AssignmentAuthorization.rejectionCode
        }
    }

    private static func sanitizedTransportError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return URLError(.unknown)
        }
        // Keep the platform classification, but discard request/response details in userInfo.
        return URLError(urlError.code)
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
    internal func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void
    ) {
        let task = self.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            completion(.success((data, httpResponse)))
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
            // Pass every HTTP status through, like the ordinary transport, so error bodies reach the shared handler.
            guard let data, let response = response as? HTTPURLResponse else {
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
