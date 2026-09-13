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
    let isEnabled: Bool
    let authorization: Flags.AssignmentAuthorization?
}

internal final class AssignmentAuthorizationStore {
    private struct State {
        var isEnabled: Bool
        var authorization: Flags.AssignmentAuthorization?
    }

    @ReadWriteLock
    private var state: State
    private let expirationLock = NSLock()
    private var expirationWorkItem: DispatchWorkItem?
    private var expirationHandler: (() -> Void)?

    init(initialAuthorization: Flags.AssignmentAuthorization?) {
        state = State(
            isEnabled: initialAuthorization != nil,
            authorization: initialAuthorization
        )
        scheduleExpiration(for: initialAuthorization)
    }

    func snapshot(at date: Date = Date()) -> AssignmentAuthorizationSnapshot {
        let state = state
        let authorization = state.authorization.flatMap { $0.expiresAt > date ? $0 : nil }
        return AssignmentAuthorizationSnapshot(
            isEnabled: state.isEnabled,
            authorization: authorization
        )
    }

    func update(_ authorization: Flags.AssignmentAuthorization?) {
        expirationLock.lock()
        _state.mutate {
            $0.isEnabled = true
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
        Data(SHA256.hash(data: Data(compactJWT.utf8))).map {
            String(format: "%02x", $0)
        }.joined()
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
}

internal struct VerifiedFlagAssignments {
    let flags: [String: FlagAssignment]
    let authorizationBinding: AssignmentAuthorizationBinding?
}

extension FlagAssignmentsFetching {
    func verifiedFlagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<VerifiedFlagAssignments, FlagsError>) -> Void
    ) {
        flagAssignments(for: evaluationContext) { result in
            completion(result.map { VerifiedFlagAssignments(flags: $0, authorizationBinding: nil) })
        }
    }
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?

    private let featureScope: any FeatureScope
    private let fetch: (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void
    private let verify: (URLRequest, FetchedFlagAssignments, String) throws -> Void
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

        let urlSession = URLSession(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            authorizationStore: authorizationStore,
            fetch: urlSession.fetch,
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
        verify: @escaping (URLRequest, FetchedFlagAssignments, String) throws -> Void,
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
                if authorizationSnapshot.isEnabled {
                    guard let authorization = authorizationSnapshot.authorization else {
                        completion(.failure(.invalidConfiguration))
                        return
                    }
                    request.setValue("Bearer \(authorization.bearerToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("2", forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader)
                    request.setValue(try self.makeNonce(), forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader)
                }
                self.fetch(request) { [featureScope] result in
                    switch result {
                    case .success(let fetched):
                        do {
                            if authorizationSnapshot.isEnabled {
                                try self.verify(request, fetched, context.clientToken)
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

                            if authorizationSnapshot.isEnabled,
                               response.subject != evaluationContext.targetingKey {
                                throw SignedAssignmentVerificationError.invalidSubject
                            }
                            let binding = authorizationSnapshot.authorization.map {
                                AssignmentAuthorizationBinding(
                                    compactJWTSHA256: AssignmentAuthorizationStore.digest(of: $0.bearerToken),
                                    policyVersion: fetched.response.value(
                                        forHTTPHeaderField: SignedAssignmentVerifier.authorizationPolicyVersionHeader
                                    ) ?? ""
                                )
                            }
                            completion(.success(VerifiedFlagAssignments(
                                flags: response.flags,
                                authorizationBinding: binding
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
                DD.logger.error("Failed to encode flag assignments request body.", error: error)
                featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
                completion(.failure(.invalidConfiguration))
            }
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

internal enum SignedAssignmentVerifier {
    static let signatureVersionHeader = "x-dd-ffe-signature-version"
    static let requestNonceHeader = "x-dd-ffe-request-nonce"
    static let authorizationPolicyVersionHeader = "x-dd-ffe-authorization-policy-version"

    private static let signatureHeader = "x-dd-ffe-signature"
    private static let certificateHeader = "x-dd-ffe-signing-certificate"
    private static let certificateIDHeader = "x-dd-ffe-certificate-id"
    private static let issuedAtHeader = "x-dd-ffe-issued-at"
    private static let expiresAtHeader = "x-dd-ffe-expires-at"
    private static let signatureDomain = "datadog.ffe.precomputed-assignments.v2"
    private static let semanticRequestHeaders = [
        "content-type",
        "dd-application-id",
        "x-rkyv",
        "x-use-cache",
        "x-dd-ffe-test-drive"
    ]
    private static let rootCertificateBase64 = "MIIBzTCCAXSgAwIBAgIUMaYCojzGfYGo+3+sbHh9qbEf0N0wCgYIKoZIzj0EAwIwMzExMC8GA1UEAwwoRGF0YWRvZyBGRkUgRWRnZSBBc3NpZ25tZW50cyBQT0MgUm9vdCBLMTAeFw0yNjA5MTEwMzE4MDhaFw0zNjA5MDgwMzE4MDhaMDMxMTAvBgNVBAMMKERhdGFkb2cgRkZFIEVkZ2UgQXNzaWdubWVudHMgUE9DIFJvb3QgSzEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASd8AStJsI0bU1Cwnl3bjgrdXAsFAkZdyX1/LSRbBrnP4aodCpiHsWP0kspNx7/Q0U0Cyk/k7FGjCPe5ViukGnno2YwZDAdBgNVHQ4EFgQUca1+zBtEI45yELrJkdqSGS1J2rgwHwYDVR0jBBgwFoAUca1+zBtEI45yELrJkdqSGS1J2rgwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwIDRwAwRAIgA3JkZVvLCmyUu3r9yyEAYufb12dItZfiA4f7KuUnqekCIFX3MOkLKGosREDoBKmdVPr0rbMh8qgF3t1aKlciltOG"

    static func makeNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(
        request: URLRequest,
        fetched: FetchedFlagAssignments,
        clientToken: String
    ) throws {
        try verify(
            request: request,
            fetched: fetched,
            clientToken: clientToken,
            currentTime: Int64(Date().timeIntervalSince1970)
        )
    }

    static func verify(
        request: URLRequest,
        fetched: FetchedFlagAssignments,
        clientToken: String,
        currentTime: Int64
    ) throws {
        guard
            fetched.response.value(forHTTPHeaderField: signatureVersionHeader) == "2",
            let nonceHex = request.value(forHTTPHeaderField: requestNonceHeader),
            let nonce = Data(hexadecimal: nonceHex), nonce.count == 16,
            let authorization = request.value(forHTTPHeaderField: "Authorization"),
            authorization.hasPrefix("Bearer "),
            !authorization.dropFirst("Bearer ".count).isEmpty,
            let policyVersion = fetched.response.value(forHTTPHeaderField: authorizationPolicyVersionHeader),
            !policyVersion.isEmpty,
            let issuedString = fetched.response.value(forHTTPHeaderField: issuedAtHeader),
            let issuedAt = Int64(issuedString),
            let expiresString = fetched.response.value(forHTTPHeaderField: expiresAtHeader),
            let expiresAt = Int64(expiresString),
            let certificateString = fetched.response.value(forHTTPHeaderField: certificateHeader),
            let certificateData = Data(base64Encoded: certificateString),
            let certificateID = fetched.response.value(forHTTPHeaderField: certificateIDHeader),
            let signatureString = fetched.response.value(forHTTPHeaderField: signatureHeader),
            let signature = Data(base64Encoded: signatureString)
        else {
            throw SignedAssignmentVerificationError.missingMetadata
        }

        guard certificateID == Data(SHA256.hash(data: certificateData)).hexadecimalString else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }

        guard
            issuedAt >= 0,
            issuedAt <= currentTime + 30,
            expiresAt >= issuedAt,
            expiresAt >= currentTime,
            expiresAt - issuedAt <= 600
        else {
            throw SignedAssignmentVerificationError.expired
        }

        guard let responseStatus = UInt16(exactly: fetched.response.statusCode) else {
            throw SignedAssignmentVerificationError.invalidMetadata
        }

        let publicKey = try trustedPublicKey(certificateData: certificateData)
        let input = signatureInput(
            nonce: nonce,
            request: request,
            requestBody: request.httpBody ?? Data(),
            compactJWT: String(authorization.dropFirst("Bearer ".count)),
            clientToken: clientToken,
            policyVersion: policyVersion,
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
    }

    private static func trustedPublicKey(certificateData: Data) throws -> SecKey {
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
        SecTrustSetAnchorCertificates(trust, [rootCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil),
              let publicKey = SecCertificateCopyKey(certificate) else {
            throw SignedAssignmentVerificationError.untrustedCertificate
        }
        return publicKey
    }

    private static func signatureInput(
        nonce: Data,
        request: URLRequest,
        requestBody: Data,
        compactJWT: String,
        clientToken: String,
        policyVersion: String,
        responseStatus: UInt16,
        issuedAt: Int64,
        expiresAt: Int64,
        responseBody: Data
    ) -> Data {
        guard let url = request.url,
              url.query == nil,
              let host = url.host,
              let method = request.httpMethod?.uppercased() else {
            return Data()
        }
        let authority: String
        if let port = url.port,
           !((url.scheme == "https" && port == 443) || (url.scheme == "http" && port == 80)) {
            authority = "\(host.lowercased()):\(port)"
        } else {
            authority = host.lowercased()
        }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        var result = Data(signatureDomain.utf8)
        result.append(0)
        result.appendLengthPrefixed(Data(method.utf8))
        result.appendLengthPrefixed(Data(authority.utf8))
        result.appendLengthPrefixed(Data(path.utf8))
        result.appendLengthPrefixed(nonce)
        result.append(contentsOf: SHA256.hash(data: requestBody))
        result.append(contentsOf: SHA256.hash(data: Data(compactJWT.utf8)))
        result.append(contentsOf: SHA256.hash(data: Data(clientToken.utf8)))
        result.appendLengthPrefixed(Data(policyVersion.utf8))
        for name in semanticRequestHeaders {
            result.appendOptionalHeader(request.value(forHTTPHeaderField: name))
        }
        result.appendBigEndian(responseStatus)
        result.appendBigEndian(UInt64(issuedAt))
        result.appendBigEndian(UInt64(expiresAt))
        result.appendBigEndian(UInt64(responseBody.count))
        result.append(contentsOf: SHA256.hash(data: responseBody))
        return result
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

    mutating func appendLengthPrefixed(_ value: Data) {
        appendBigEndian(UInt32(value.count))
        append(value)
    }

    mutating func appendOptionalHeader(_ value: String?) {
        guard let value else {
            append(0)
            return
        }
        append(1)
        appendLengthPrefixed(Data(value.utf8))
    }
}
