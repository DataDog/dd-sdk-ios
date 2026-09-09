/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit
import Security
import DatadogInternal

internal protocol FlagAssignmentsFetching {
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    )
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?

    private let featureScope: any FeatureScope
    private let fetch: (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void
    private let verify: (URLRequest, FetchedFlagAssignments, String) throws -> Void
    private let makeNonce: () throws -> String

    private static let decoder = JSONDecoder()

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let urlSession = URLSession(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            fetch: urlSession.fetch,
            verify: SignedAssignmentVerifier.verify,
            makeNonce: SignedAssignmentVerifier.makeNonce
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        fetch: @escaping (URLRequest, @escaping (Result<FetchedFlagAssignments, Error>) -> Void) -> Void,
        verify: @escaping (URLRequest, FetchedFlagAssignments, String) throws -> Void,
        makeNonce: @escaping () throws -> String
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.fetch = fetch
        self.verify = verify
        self.makeNonce = makeNonce
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
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
                request.setValue("1", forHTTPHeaderField: SignedAssignmentVerifier.signatureVersionHeader)
                request.setValue(try self.makeNonce(), forHTTPHeaderField: SignedAssignmentVerifier.requestNonceHeader)
                self.fetch(request) { [featureScope] result in
                    switch result {
                    case .success(let fetched):
                        do {
                            try self.verify(request, fetched, context.clientToken)
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

                            completion(.success(response.flags))
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
}

internal enum SignedAssignmentVerifier {
    static let signatureVersionHeader = "x-dd-ffe-signature-version"
    static let requestNonceHeader = "x-dd-ffe-request-nonce"

    private static let signatureHeader = "x-dd-ffe-signature"
    private static let certificateHeader = "x-dd-ffe-signing-certificate"
    private static let certificateIDHeader = "x-dd-ffe-certificate-id"
    private static let issuedAtHeader = "x-dd-ffe-issued-at"
    private static let expiresAtHeader = "x-dd-ffe-expires-at"
    private static let signatureDomain = "datadog.ffe.precomputed-assignments.v1"
    private static let rootCertificateBase64 = "MIIBlTCCATugAwIBAgIBATAKBggqhkjOPQQDAjAyMTAwLgYDVQQDEydEYXRhZG9nIEZGRSBTaWduZWQgQXNzaWdubWVudHMgUE9DIFJvb3QwHhcNMjYwMTAxMDAwMDAwWhcNMzYwMTAxMDAwMDAwWjAyMTAwLgYDVQQDEydEYXRhZG9nIEZGRSBTaWduZWQgQXNzaWdubWVudHMgUE9DIFJvb3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQzJMvRTfKpBAxFNBvEdLNTOK/cna8MQivOtVYnJ8qeRLVrPw01tPF8F4RaShZUqhuBa62T9uRApLe/3CZ2xkPIo0IwQDAOBgNVHQ8BAf8EBAMCAoQwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUhos9mSbUI3BmaP8jto591fzhV+IwCgYIKoZIzj0EAwIDSAAwRQIgHRu3XCCaGw1V170Cqc3JdslBV43MzyzJctlo8cuGS8kCIQCVeyCHpzf8pmvO9Oyep/JiY633sJYRfBNzQYObaeCZEw=="

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
            fetched.response.value(forHTTPHeaderField: signatureVersionHeader) == "1",
            let nonceHex = request.value(forHTTPHeaderField: requestNonceHeader),
            let nonce = Data(hexadecimal: nonceHex), nonce.count == 16,
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
            issuedAt <= currentTime + 30,
            expiresAt >= currentTime,
            expiresAt - issuedAt <= 600
        else {
            throw SignedAssignmentVerificationError.expired
        }

        let publicKey = try trustedPublicKey(certificateData: certificateData)
        let input = signatureInput(
            nonce: nonce,
            requestBody: request.httpBody ?? Data(),
            clientToken: clientToken,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            responseBody: fetched.data
        )
        var verificationError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            input as CFData,
            signature as CFData,
            &verificationError
        ) else {
            throw verificationError?.takeRetainedValue()
                ?? SignedAssignmentVerificationError.invalidSignature
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
        requestBody: Data,
        clientToken: String,
        issuedAt: Int64,
        expiresAt: Int64,
        responseBody: Data
    ) -> Data {
        var result = Data(signatureDomain.utf8)
        result.append(0)
        result.appendBigEndian(UInt32(nonce.count))
        result.append(nonce)
        result.append(contentsOf: SHA256.hash(data: requestBody))
        result.append(contentsOf: SHA256.hash(data: Data(clientToken.utf8)))
        result.appendBigEndian(UInt64(issuedAt))
        result.appendBigEndian(UInt64(expiresAt))
        result.appendBigEndian(UInt64(responseBody.count))
        result.append(responseBody)
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
}
