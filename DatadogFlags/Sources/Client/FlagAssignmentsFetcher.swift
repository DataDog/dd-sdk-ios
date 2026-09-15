/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit
import Security
import DatadogInternal

internal struct AssignmentAuthorizationBinding: Codable, Equatable {
    let compactJWTSHA256: String
    let policyVersion: String
}

internal struct AssignmentAuthorizationSnapshot {
    let protection: Flags.AssignmentProtection
    let authorization: Flags.AssignmentAuthorization?
}

internal final class AssignmentAuthorizationStore {
    private struct State {
        var authorization: Flags.AssignmentAuthorization?
    }

    let protection: Flags.AssignmentProtection

    @ReadWriteLock
    private var state: State
    private let expirationLock = NSLock()
    private var expirationWorkItem: DispatchWorkItem?
    private var expirationHandler: (() -> Void)?

    init(
        initialAuthorization: Flags.AssignmentAuthorization?,
        protection: Flags.AssignmentProtection = .disabled
    ) {
        self.protection = protection
        state = State(authorization: initialAuthorization)
        scheduleExpiration(for: initialAuthorization)
    }

    func snapshot(at date: Date = Date()) -> AssignmentAuthorizationSnapshot {
        let state = state
        let authorization = state.authorization.flatMap { $0.expiresAt > date ? $0 : nil }
        return AssignmentAuthorizationSnapshot(
            protection: protection,
            authorization: authorization
        )
    }

    func update(_ authorization: Flags.AssignmentAuthorization?) {
        expirationLock.lock()
        _state.mutate {
            $0.authorization = authorization
        }
        scheduleExpirationLocked(for: authorization)
        expirationLock.unlock()
    }

    func setExpirationHandler(_ handler: @escaping () -> Void) {
        expirationLock.lock()
        expirationHandler = handler
        expirationLock.unlock()
    }

    private func scheduleExpiration(for authorization: Flags.AssignmentAuthorization?) {
        expirationLock.lock()
        scheduleExpirationLocked(for: authorization)
        expirationLock.unlock()
    }

    private func scheduleExpirationLocked(for authorization: Flags.AssignmentAuthorization?) {
        expirationWorkItem?.cancel()
        guard let authorization else {
            expirationWorkItem = nil
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.expire(authorization, at: Date())
        }
        expirationWorkItem = workItem

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, authorization.expiresAt.timeIntervalSinceNow),
            execute: workItem
        )
    }

    func expireIfNeeded(at date: Date = Date()) {
        guard let authorization = state.authorization else {
            return
        }
        expire(authorization, at: date)
    }

    private func expire(_ scheduledAuthorization: Flags.AssignmentAuthorization, at date: Date) {
        expirationLock.lock()
        var didExpire = false
        _state.mutate { state in
            guard state.authorization == scheduledAuthorization,
                  scheduledAuthorization.expiresAt <= date else {
                return
            }
            state.authorization = nil
            didExpire = true
        }
        guard didExpire else {
            if state.authorization == scheduledAuthorization {
                scheduleExpirationLocked(for: scheduledAuthorization)
            }
            expirationLock.unlock()
            return
        }

        let handler = expirationHandler
        expirationWorkItem = nil
        expirationLock.unlock()
        handler?()
    }

    static func digest(of compactJWT: String) -> String {
        Data(SHA256.hash(data: Data(compactJWT.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

internal protocol FlagAssignmentsFetching {
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    )

    func verifiedFlagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<VerifiedFlagAssignments, FlagsError>) -> Void
    )

    func validatePersistedFlagAssignments(
        _ flagsData: FlagsData,
        at date: Date,
        completion: @escaping (Bool) -> Void
    )
}

internal struct VerifiedFlagAssignments {
    let flags: [String: FlagAssignment]
    let signedPayload: PersistedSignedAssignmentPayload?
}

extension FlagAssignmentsFetching {
    func verifiedFlagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<VerifiedFlagAssignments, FlagsError>) -> Void
    ) {
        flagAssignments(for: evaluationContext) { result in
            completion(result.map { VerifiedFlagAssignments(flags: $0, signedPayload: nil) })
        }
    }

    func validatePersistedFlagAssignments(
        _ flagsData: FlagsData,
        at date: Date,
        completion: @escaping (Bool) -> Void
    ) {
        completion(flagsData.signedPayload == nil)
    }
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?

    private let featureScope: any FeatureScope
    private let fetch: (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void
    private let verify: (
        URLRequest,
        FetchedFlagAssignments,
        String,
        Flags.AssignmentProtection,
        Int64
    ) throws -> SignedAssignmentVerificationMetadata
    private let makeNonce: () throws -> String
    private let authorizationStore: AssignmentAuthorizationStore

    private static let decoder = JSONDecoder()

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        authorizationStore: AssignmentAuthorizationStore
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let fetch: (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void
        if authorizationStore.protection == .disabled {
            let urlSession = URLSession(configuration: configuration)
            fetch = urlSession.fetch
        } else {
            let httpClient = FlagAssignmentsHTTPClient(
                configuration: configuration,
                maximumResponseBytes: SignedAssignmentVerifier.maximumResponseBodyBytes
            )
            fetch = httpClient.fetch
        }

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            authorizationStore: authorizationStore,
            fetch: fetch,
            verify: SignedAssignmentVerifier.verify,
            makeNonce: SignedAssignmentVerifier.makeNonce
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        authorizationStore: AssignmentAuthorizationStore = AssignmentAuthorizationStore(initialAuthorization: nil),
        fetch: @escaping (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void,
        verify: @escaping (
            URLRequest,
            FetchedFlagAssignments,
            String,
            Flags.AssignmentProtection,
            Int64
        ) throws -> SignedAssignmentVerificationMetadata,
        makeNonce: @escaping () throws -> String
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.authorizationStore = authorizationStore
        self.fetch = fetch
        self.verify = verify
        self.makeNonce = makeNonce
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        verifiedFlagAssignments(for: evaluationContext) { result in
            completion(result.map(\.flags))
        }
    }

    func verifiedFlagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<VerifiedFlagAssignments, FlagsError>) -> Void
    ) {
        featureScope.context { [weak self] context in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            do {
                var request = try URLRequest.flagAssignmentsRequest(
                    url: self.url(with: context),
                    evaluationContext: evaluationContext,
                    context: context,
                    customHeaders: self.customHeaders
                )
                let authorizationSnapshot = self.authorizationStore.snapshot()
                switch authorizationSnapshot.protection {
                case .disabled:
                    break
                case .signed:
                    try SignedAssignmentVerifier.validateRequestBeforeAddingProtectionHeaders(
                        request: request,
                        clientToken: context.clientToken,
                        protection: .signed,
                        compactJWT: nil
                    )
                    request.setValue("2", forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader)
                    request.setValue(try self.makeNonce(), forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader)
                case .signedAndAuthorized:
                    guard let authorization = authorizationSnapshot.authorization else {
                        completion(.failure(.invalidConfiguration))
                        return
                    }
                    try SignedAssignmentVerifier.validateRequestBeforeAddingProtectionHeaders(
                        request: request,
                        clientToken: context.clientToken,
                        protection: .signedAndAuthorized,
                        compactJWT: authorization.bearerToken
                    )
                    request.setValue("Bearer \(authorization.bearerToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("2", forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader)
                    request.setValue(try self.makeNonce(), forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader)
                }
                self.fetch(request) { [featureScope] result in
                    switch result {
                    case .success(let fetched):
                        do {
                            let verificationMetadata: SignedAssignmentVerificationMetadata?
                            if authorizationSnapshot.protection == .disabled {
                                verificationMetadata = nil
                            } else {
                                verificationMetadata = try self.verify(
                                    request,
                                    fetched,
                                    context.clientToken,
                                    authorizationSnapshot.protection,
                                    Int64(Date().timeIntervalSince1970)
                                )
                            }
                            let response = try Self.decoder.decode(
                                FlagAssignmentsResponse.self,
                                from: fetched.data
                            )

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

                            if authorizationSnapshot.protection != .disabled,
                               response.subject != evaluationContext.targetingKey {
                                throw SignedAssignmentVerificationError.invalidSubject
                            }
                            let signedPayload = try verificationMetadata.map {
                                try self.makePersistedSignedPayload(
                                    protection: authorizationSnapshot.protection,
                                    authorization: authorizationSnapshot.authorization,
                                    request: request,
                                    fetched: fetched,
                                    context: context,
                                    subject: evaluationContext.targetingKey,
                                    metadata: $0
                                )
                            }
                            completion(.success(VerifiedFlagAssignments(
                                flags: response.flags,
                                signedPayload: signedPayload
                            )))
                        } catch let error as SignedAssignmentVerificationError {
                            DD.logger.error("Rejected an unverified flag assignments response.", error: error)
                            featureScope.telemetry.error(
                                "Rejected an unverified flag assignments response",
                                error: error
                            )
                            completion(.failure(.invalidResponse))
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
            } catch let error {
                DD.logger.error("Failed to create a valid flag assignments request.", error: error)
                featureScope.telemetry.error("Failed to create a valid flag assignments request.", error: error)
                completion(.failure(.invalidConfiguration))
            }
        }
    }

    func validatePersistedFlagAssignments(
        _ flagsData: FlagsData,
        at date: Date,
        completion: @escaping (Bool) -> Void
    ) {
        let authorizationSnapshot = authorizationStore.snapshot(at: date)
        guard authorizationSnapshot.protection != .disabled else {
            completion(flagsData.signedPayload == nil)
            return
        }
        guard let signedPayload = flagsData.signedPayload,
              signedPayload.protection == authorizationSnapshot.protection else {
            completion(false)
            return
        }

        featureScope.context { [weak self] context in
            guard let self else {
                completion(false)
                return
            }
            do {
                guard signedPayload.endpoint == self.url(with: context),
                      signedPayload.environment == context.env,
                      signedPayload.subject == flagsData.context.targetingKey,
                      signedPayload.clientTokenSHA256 == AssignmentAuthorizationStore.digest(of: context.clientToken),
                      signedPayload.expiresAt > date,
                      signedPayload.issuedAt <= date.addingTimeInterval(SignedAssignmentVerifier.maximumClockSkew) else {
                    completion(false)
                    return
                }

                var request = URLRequest(url: signedPayload.endpoint)
                request.httpMethod = "POST"
                request.httpBody = signedPayload.requestBody
                request.setValue(context.clientToken, forHTTPHeaderField: "dd-client-token")
                for (name, value) in signedPayload.requestHeaders {
                    request.setValue(value, forHTTPHeaderField: name)
                }

                switch authorizationSnapshot.protection {
                case .disabled:
                    completion(false)
                    return
                case .signed:
                    guard authorizationSnapshot.authorization == nil,
                          signedPayload.authorizationBinding == nil else {
                        completion(false)
                        return
                    }
                case .signedAndAuthorized:
                    guard let authorization = authorizationSnapshot.authorization,
                          signedPayload.authorizationBinding?.compactJWTSHA256
                            == AssignmentAuthorizationStore.digest(of: authorization.bearerToken) else {
                        completion(false)
                        return
                    }
                    request.setValue("Bearer \(authorization.bearerToken)", forHTTPHeaderField: "Authorization")
                }

                guard let response = HTTPURLResponse(
                    url: signedPayload.endpoint,
                    statusCode: signedPayload.responseStatus,
                    httpVersion: nil,
                    headerFields: signedPayload.responseHeaders
                ) else {
                    completion(false)
                    return
                }
                let fetched = FetchedFlagAssignments(data: signedPayload.responseBody, response: response)
                let metadata = try self.verify(
                    request,
                    fetched,
                    context.clientToken,
                    authorizationSnapshot.protection,
                    Int64(date.timeIntervalSince1970)
                )
                let requestBody = try Self.decoder.decode(
                    FlagAssignmentsRequestBody.self,
                    from: signedPayload.requestBody
                )
                let responseBody = try Self.decoder.decode(
                    FlagAssignmentsResponse.self,
                    from: signedPayload.responseBody
                )
                let expectedBinding = authorizationSnapshot.authorization.map {
                    AssignmentAuthorizationBinding(
                        compactJWTSHA256: AssignmentAuthorizationStore.digest(of: $0.bearerToken),
                        policyVersion: metadata.authorizationPolicyVersion ?? ""
                    )
                }
                let isValid = requestBody.environment.datadogEnvironment == context.env
                    && requestBody.subject.targetingKey == flagsData.context.targetingKey
                    && requestBody.subject.targetingAttributes == flagsData.context.attributes
                    && responseBody.subject == flagsData.context.targetingKey
                    && responseBody.flags == flagsData.flags
                    && metadata.certificateID == signedPayload.certificateID
                    && metadata.rulesRevision == signedPayload.rulesRevision
                    && Date(timeIntervalSince1970: TimeInterval(metadata.issuedAt)) == signedPayload.issuedAt
                    && Date(timeIntervalSince1970: TimeInterval(metadata.expiresAt)) == signedPayload.expiresAt
                    && expectedBinding == signedPayload.authorizationBinding
                completion(isValid)
            } catch {
                completion(false)
            }
        }
    }

    private func makePersistedSignedPayload(
        protection: Flags.AssignmentProtection,
        authorization: Flags.AssignmentAuthorization?,
        request: URLRequest,
        fetched: FetchedFlagAssignments,
        context: DatadogContext,
        subject: String,
        metadata: SignedAssignmentVerificationMetadata
    ) throws -> PersistedSignedAssignmentPayload {
        guard let endpoint = request.url else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        let authorizationBinding: AssignmentAuthorizationBinding?
        switch protection {
        case .disabled:
            throw SignedAssignmentVerificationError.invalidMetadata
        case .signed:
            guard authorization == nil, metadata.authorizationPolicyVersion == nil else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            authorizationBinding = nil
        case .signedAndAuthorized:
            guard let authorization,
                  let policyVersion = metadata.authorizationPolicyVersion,
                  !policyVersion.isEmpty else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            authorizationBinding = AssignmentAuthorizationBinding(
                compactJWTSHA256: AssignmentAuthorizationStore.digest(of: authorization.bearerToken),
                policyVersion: policyVersion
            )
        }
        return PersistedSignedAssignmentPayload(
            protection: protection,
            endpoint: endpoint,
            environment: context.env,
            subject: subject,
            clientTokenSHA256: AssignmentAuthorizationStore.digest(of: context.clientToken),
            authorizationBinding: authorizationBinding,
            requestBody: request.httpBody ?? Data(),
            requestHeaders: SignedAssignmentVerifier.persistedRequestHeaders(from: request),
            responseStatus: fetched.response.statusCode,
            responseBody: fetched.data,
            responseHeaders: SignedAssignmentVerifier.persistedResponseHeaders(from: fetched.response),
            certificateID: metadata.certificateID,
            rulesRevision: metadata.rulesRevision,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(metadata.issuedAt)),
            expiresAt: Date(timeIntervalSince1970: TimeInterval(metadata.expiresAt))
        )
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
        completion: @escaping (Result<FetchedFlagAssignments, Error>) -> Void
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

            completion(.success(FetchedFlagAssignments(data: data, response: httpResponse)))
        }
        task.resume()
    }
}

/// Buffers protected responses up to a fixed limit.
///
/// `URLSession.dataTask(with:completionHandler:)` buffers the complete body before the callback.
/// This delegate stops accumulation when the declared or received body exceeds the limit.
internal final class FlagAssignmentsHTTPClient {
    private let delegate: FlagAssignmentsSessionDelegate
    private let session: URLSession

    init(configuration: URLSessionConfiguration, maximumResponseBytes: Int) {
        let delegate = FlagAssignmentsSessionDelegate(maximumResponseBytes: maximumResponseBytes)
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<FetchedFlagAssignments, Error>) -> Void
    ) {
        let task = session.dataTask(with: request)
        delegate.register(task: task, completion: completion)
        task.resume()
    }
}

private final class FlagAssignmentsSessionDelegate: NSObject, URLSessionDataDelegate {
    private final class TaskState {
        let completion: (Result<FetchedFlagAssignments, Error>) -> Void
        var response: HTTPURLResponse?
        var data = Data()
        var terminalError: Error?

        init(completion: @escaping (Result<FetchedFlagAssignments, Error>) -> Void) {
            self.completion = completion
        }
    }

    private let maximumResponseBytes: Int
    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]

    init(maximumResponseBytes: Int) {
        precondition(maximumResponseBytes >= 0)
        self.maximumResponseBytes = maximumResponseBytes
    }

    func register(
        task: URLSessionDataTask,
        completion: @escaping (Result<FetchedFlagAssignments, Error>) -> Void
    ) {
        lock.lock()
        states[task.taskIdentifier] = TaskState(completion: completion)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        var disposition: URLSession.ResponseDisposition = .allow
        lock.lock()
        if let state = states[dataTask.taskIdentifier] {
            guard let response = response as? HTTPURLResponse,
                  200..<300 ~= response.statusCode else {
                state.terminalError = URLError(.badServerResponse)
                lock.unlock()
                completionHandler(.cancel)
                return
            }
            if response.expectedContentLength > Int64(maximumResponseBytes) {
                state.terminalError = URLError(.dataLengthExceedsMaximum)
                disposition = .cancel
            } else {
                state.response = response
                if response.expectedContentLength > 0 {
                    state.data.reserveCapacity(Int(response.expectedContentLength))
                }
            }
        }
        lock.unlock()
        completionHandler(disposition)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var shouldCancel = false
        lock.lock()
        if let state = states[dataTask.taskIdentifier], state.terminalError == nil {
            if data.count > maximumResponseBytes
                || state.data.count > maximumResponseBytes - data.count {
                state.terminalError = URLError(.dataLengthExceedsMaximum)
                shouldCancel = true
            } else {
                state.data.append(data)
            }
        }
        lock.unlock()
        if shouldCancel {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let state = states.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let state else {
            return
        }
        if let error = state.terminalError ?? error {
            state.completion(.failure(error))
        } else if let response = state.response {
            state.completion(.success(FetchedFlagAssignments(data: state.data, response: response)))
        } else {
            state.completion(.failure(URLError(.badServerResponse)))
        }
    }
}

internal struct FetchedFlagAssignments {
    let data: Data
    let response: HTTPURLResponse
}

internal enum SignedAssignmentVerificationError: Error {
    case missingMetadata
    case invalidMetadata
    case expired
    case untrustedCertificate
    case invalidSignature
    case invalidSubject
}

internal struct SignedAssignmentVerificationMetadata: Equatable {
    let certificateID: String
    let rulesRevision: String
    let issuedAt: Int64
    let expiresAt: Int64
    let authorizationPolicyVersion: String?
}

internal enum SignedAssignmentVerifier {
    static let signatureVersionHeader = "x-datadog-feature-flags-signature-version"
    static let requestNonceHeader = "x-datadog-feature-flags-request-nonce"
    static let authorizationPolicyVersionHeader = "x-datadog-feature-flags-authorization-policy-version"
    static let rulesRevisionHeader = "x-datadog-feature-flags-rules-revision"
    static let maximumClockSkew: TimeInterval = 30

    private static let signatureHeader = "x-datadog-feature-flags-signature"
    private static let certificateHeader = "x-datadog-feature-flags-signing-certificate"
    private static let certificateIDHeader = "x-datadog-feature-flags-certificate-id"
    private static let issuedAtHeader = "x-datadog-feature-flags-issued-at"
    private static let expiresAtHeader = "x-datadog-feature-flags-expires-at"
    private static let signatureDomain = "datadog.feature-flags.precomputed-assignments.v2"
    private static let semanticRequestHeaders = [
        "content-type",
        "dd-application-id",
        "x-rkyv",
        "x-use-cache"
    ]
    private static let maximumCertificateHeaderBytes = 8_192
    private static let maximumSignatureHeaderBytes = 256
    private static let maximumCertificateBytes = 4_096
    private static let maximumSignatureBytes = 80
    private static let maximumAuthorizationBytes = 4_096
    private static let maximumClientTokenBytes = 512
    private static let maximumRequestBodyBytes = 1_024 * 1_024
    static let maximumResponseBodyBytes = 2 * 1_024 * 1_024
    private static let maximumURLComponentBytes = 2_048
    private static let maximumPolicyVersionBytes = 256
    private static let maximumRulesRevisionBytes = 256
    private static let maximumTimestampBytes = 20
    private static let rootCertificateBase64 = "MIIBzTCCAXSgAwIBAgIUMaYCojzGfYGo+3+sbHh9qbEf0N0wCgYIKoZIzj0EAwIwMzExMC8GA1UEAwwoRGF0YWRvZyBGRkUgRWRnZSBBc3NpZ25tZW50cyBQT0MgUm9vdCBLMTAeFw0yNjA5MTEwMzE4MDhaFw0zNjA5MDgwMzE4MDhaMDMxMTAvBgNVBAMMKERhdGFkb2cgRkZFIEVkZ2UgQXNzaWdubWVudHMgUE9DIFJvb3QgSzEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASd8AStJsI0bU1Cwnl3bjgrdXAsFAkZdyX1/LSRbBrnP4aodCpiHsWP0kspNx7/Q0U0Cyk/k7FGjCPe5ViukGnno2YwZDAdBgNVHQ4EFgQUca1+zBtEI45yELrJkdqSGS1J2rgwHwYDVR0jBBgwFoAUca1+zBtEI45yELrJkdqSGS1J2rgwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwIDRwAwRAIgA3JkZVvLCmyUu3r9yyEAYufb12dItZfiA4f7KuUnqekCIFX3MOkLKGosREDoBKmdVPr0rbMh8qgF3t1aKlciltOG"

    static func makeNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func validateRequestBeforeAddingProtectionHeaders(
        request: URLRequest,
        clientToken: String,
        protection: Flags.AssignmentProtection,
        compactJWT: String?
    ) throws {
        guard protection != .disabled,
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: signatureVersionHeader) == nil,
              request.value(forHTTPHeaderField: requestNonceHeader) == nil,
              request.value(forHTTPHeaderField: "dd-client-token") == clientToken else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        _ = try requestComponents(request: request, clientToken: clientToken)
        switch protection {
        case .disabled:
            throw SignedAssignmentVerificationError.invalidMetadata
        case .signed:
            guard compactJWT == nil else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
        case .signedAndAuthorized:
            guard let compactJWT else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            try validateCompactJWT(compactJWT)
        }
    }

    static func verify(
        request: URLRequest,
        fetched: FetchedFlagAssignments,
        clientToken: String,
        protection: Flags.AssignmentProtection,
        currentTime: Int64
    ) throws -> SignedAssignmentVerificationMetadata {
        guard protection != .disabled,
              fetched.data.count <= maximumResponseBodyBytes,
              request.value(forHTTPHeaderField: signatureVersionHeader) == "2",
              fetched.response.url == request.url else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        _ = try requestComponents(request: request, clientToken: clientToken)

        let authorization: String?
        let policyVersion: String?
        guard let rulesRevision = fetched.response.value(forHTTPHeaderField: rulesRevisionHeader) else {
            throw SignedAssignmentVerificationError.missingMetadata
        }
        guard isValidRulesRevision(rulesRevision) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        switch protection {
        case .disabled:
            throw SignedAssignmentVerificationError.invalidMetadata
        case .signed:
            guard request.value(forHTTPHeaderField: "Authorization") == nil,
                  fetched.response.value(forHTTPHeaderField: authorizationPolicyVersionHeader) == nil else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            authorization = nil
            policyVersion = nil
        case .signedAndAuthorized:
            guard let header = request.value(forHTTPHeaderField: "Authorization"),
                  header.hasPrefix("Bearer "),
                  header.utf8.count <= maximumAuthorizationBytes + "Bearer ".utf8.count,
                  let responsePolicyVersion = fetched.response.value(
                    forHTTPHeaderField: authorizationPolicyVersionHeader
                  ),
                  !responsePolicyVersion.isEmpty,
                  responsePolicyVersion.utf8.count <= maximumPolicyVersionBytes else {
                throw SignedAssignmentVerificationError.missingMetadata
            }
            let compactJWT = String(header.dropFirst("Bearer ".count))
            try validateCompactJWT(compactJWT)
            authorization = compactJWT
            policyVersion = responsePolicyVersion
        }

        guard
            fetched.response.value(forHTTPHeaderField: signatureVersionHeader) == "2",
            let nonceHex = request.value(forHTTPHeaderField: requestNonceHeader),
            nonceHex.utf8.count == 32,
            let nonce = Data(hexadecimal: nonceHex),
            nonce.count == 16,
            let issuedString = fetched.response.value(forHTTPHeaderField: issuedAtHeader),
            issuedString.utf8.count <= maximumTimestampBytes,
            let issuedAt = Int64(issuedString),
            String(issuedAt) == issuedString,
            let expiresString = fetched.response.value(forHTTPHeaderField: expiresAtHeader),
            expiresString.utf8.count <= maximumTimestampBytes,
            let expiresAt = Int64(expiresString),
            String(expiresAt) == expiresString,
            let certificateString = fetched.response.value(forHTTPHeaderField: certificateHeader),
            certificateString.utf8.count <= maximumCertificateHeaderBytes,
            let certificateData = Data(base64Encoded: certificateString),
            !certificateData.isEmpty,
            certificateData.count <= maximumCertificateBytes,
            let certificateID = fetched.response.value(forHTTPHeaderField: certificateIDHeader),
            certificateID.utf8.count == 64,
            let signatureString = fetched.response.value(forHTTPHeaderField: signatureHeader),
            signatureString.utf8.count <= maximumSignatureHeaderBytes,
            let signature = Data(base64Encoded: signatureString),
            !signature.isEmpty,
            signature.count <= maximumSignatureBytes
        else {
            throw SignedAssignmentVerificationError.missingMetadata
        }

        guard certificateID == Data(SHA256.hash(data: certificateData)).hexadecimalString else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }

        guard
            issuedAt >= 0,
            issuedAt <= currentTime + Int64(maximumClockSkew),
            expiresAt >= issuedAt,
            expiresAt > currentTime,
            expiresAt - issuedAt <= 300
        else {
            throw SignedAssignmentVerificationError.expired
        }

        guard let responseStatus = UInt16(exactly: fetched.response.statusCode) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }

        let publicKey = try trustedPublicKey(
            certificateData: certificateData,
            verificationTime: currentTime
        )
        let input = try signatureInput(
            nonce: nonce,
            request: request,
            requestBody: request.httpBody ?? Data(),
            compactJWT: authorization,
            clientToken: clientToken,
            policyVersion: policyVersion,
            rulesRevision: rulesRevision,
            responseStatus: responseStatus,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            responseBody: fetched.data
        )
        guard SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            input as CFData,
            signature as CFData,
            nil
        ) else {
            throw SignedAssignmentVerificationError.invalidSignature
        }
        return SignedAssignmentVerificationMetadata(
            certificateID: certificateID,
            rulesRevision: rulesRevision,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            authorizationPolicyVersion: policyVersion
        )
    }

    private static func trustedPublicKey(
        certificateData: Data,
        verificationTime: Int64
    ) throws -> SecKey {
        guard
            let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
            let rootData = Data(base64Encoded: rootCertificateBase64),
            let rootCertificate = SecCertificateCreateWithData(nil, rootData as CFData)
        else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess,
              let trust else {
            throw SignedAssignmentVerificationError.untrustedCertificate
        }
        guard SecTrustSetAnchorCertificates(trust, [rootCertificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetVerifyDate(
                trust,
                Date(timeIntervalSince1970: TimeInterval(verificationTime)) as CFDate
              ) == errSecSuccess else {
            throw SignedAssignmentVerificationError.untrustedCertificate
        }
        guard SecTrustEvaluateWithError(trust, nil),
              let publicKey = SecCertificateCopyKey(certificate) else {
            throw SignedAssignmentVerificationError.untrustedCertificate
        }
        guard let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
              attributes[kSecAttrKeyType] as? String == String(kSecAttrKeyTypeECSECPrimeRandom),
              attributes[kSecAttrKeySizeInBits] as? Int == 256 else {
            throw SignedAssignmentVerificationError.untrustedCertificate
        }
        return publicKey
    }

    private static func requestComponents(
        request: URLRequest,
        clientToken: String
    ) throws -> (method: String, scheme: String, authority: String, path: String) {
        guard let url = request.url,
              url.query == nil,
              url.fragment == nil,
              url.user == nil,
              url.password == nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty,
              let method = request.httpMethod?.uppercased(),
              method == "POST",
              request.value(forHTTPHeaderField: "dd-client-token") == clientToken else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        let authority: String
        if let port = url.port, port != 443 {
            authority = "\(host.lowercased()):\(port)"
        } else {
            authority = host.lowercased()
        }
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        let path = encodedPath.isEmpty ? "/" : encodedPath
        guard method.utf8.count <= maximumURLComponentBytes,
              scheme.utf8.count <= maximumURLComponentBytes,
              authority.utf8.count <= maximumURLComponentBytes,
              path.utf8.count <= maximumURLComponentBytes,
              (request.httpBody?.count ?? 0) <= maximumRequestBodyBytes,
              clientToken.utf8.count <= maximumClientTokenBytes else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        return (method, scheme, authority, path)
    }

    private static func validateCompactJWT(_ compactJWT: String) throws {
        guard !compactJWT.isEmpty,
              compactJWT.utf8.count <= maximumAuthorizationBytes else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        let segments = compactJWT.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              segments.allSatisfy({ segment in
                  !segment.isEmpty && segment.unicodeScalars.allSatisfy { scalar in
                      switch scalar.value {
                      case 45, 48...57, 65...90, 95, 97...122:
                          return true
                      default:
                          return false
                      }
                  }
              }) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
    }

    static func signatureInput(
        nonce: Data,
        request: URLRequest,
        requestBody: Data,
        compactJWT: String?,
        clientToken: String,
        policyVersion: String?,
        rulesRevision: String,
        responseStatus: UInt16,
        issuedAt: Int64,
        expiresAt: Int64,
        responseBody: Data
    ) throws -> Data {
        let components = try requestComponents(request: request, clientToken: clientToken)
        guard requestBody == (request.httpBody ?? Data()),
              requestBody.count <= maximumRequestBodyBytes,
              responseBody.count <= maximumResponseBodyBytes,
              (compactJWT?.utf8.count ?? 0) <= maximumAuthorizationBytes,
              (policyVersion?.utf8.count ?? 0) <= maximumPolicyVersionBytes,
              isValidRulesRevision(rulesRevision) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        var result = Data(signatureDomain.utf8)
        result.append(0)
        try result.appendLengthPrefixed(Data(components.method.utf8))
        try result.appendLengthPrefixed(Data(components.scheme.utf8))
        try result.appendLengthPrefixed(Data(components.authority.utf8))
        try result.appendLengthPrefixed(Data(components.path.utf8))
        try result.appendLengthPrefixed(nonce)
        result.append(contentsOf: SHA256.hash(data: requestBody))
        if let compactJWT {
            guard let policyVersion else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            result.append(1)
            result.append(contentsOf: SHA256.hash(data: Data(compactJWT.utf8)))
            result.append(contentsOf: SHA256.hash(data: Data(clientToken.utf8)))
            try result.appendLengthPrefixed(Data(policyVersion.utf8))
        } else {
            guard policyVersion == nil else {
                throw SignedAssignmentVerificationError.invalidMetadata
            }
            result.append(0)
            result.append(contentsOf: SHA256.hash(data: Data(clientToken.utf8)))
        }
        try result.appendLengthPrefixed(Data(rulesRevision.utf8))
        for name in semanticRequestHeaders {
            try result.appendOptionalHeader(request.value(forHTTPHeaderField: name))
        }
        result.appendBigEndian(responseStatus)
        guard let encodedIssuedAt = UInt64(exactly: issuedAt),
              let encodedExpiresAt = UInt64(exactly: expiresAt) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        result.appendBigEndian(encodedIssuedAt)
        result.appendBigEndian(encodedExpiresAt)
        result.appendBigEndian(UInt64(responseBody.count))
        result.append(contentsOf: SHA256.hash(data: responseBody))
        return result
    }

    /// The origin artifact identifier is opaque to the SDK. Limit it to the
    /// RFC 3986 unreserved character set so all HTTP stacks preserve it exactly.
    private static func isValidRulesRevision(_ value: String) -> Bool {
        let bytes = value.utf8
        guard !bytes.isEmpty, bytes.count <= maximumRulesRevisionBytes else {
            return false
        }
        return bytes.allSatisfy { byte in
            (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2D
                || byte == 0x2E
                || byte == 0x5F
                || byte == 0x7E
        }
    }

    static func persistedRequestHeaders(from request: URLRequest) -> [String: String] {
        ([signatureVersionHeader, requestNonceHeader] + semanticRequestHeaders).reduce(into: [:]) { result, name in
            if let value = request.value(forHTTPHeaderField: name) {
                result[name] = value
            }
        }
    }

    static func persistedResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
        [
            signatureVersionHeader,
            authorizationPolicyVersionHeader,
            rulesRevisionHeader,
            signatureHeader,
            certificateHeader,
            certificateIDHeader,
            issuedAtHeader,
            expiresAtHeader
        ].reduce(into: [:]) { result, name in
            if let value = response.value(forHTTPHeaderField: name) {
                result[name] = value
            }
        }
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexadecimal: String) {
        guard hexadecimal.count.isMultiple(of: 2) else {
            return nil
        }
        var data = Data(capacity: hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendLengthPrefixed(_ value: Data) throws {
        guard let size = UInt32(exactly: value.count) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        appendBigEndian(size)
        append(value)
    }

    mutating func appendOptionalHeader(_ value: String?) throws {
        guard let value else {
            append(0)
            return
        }
        append(1)
        try appendLengthPrefixed(Data(value.utf8))
    }
}
