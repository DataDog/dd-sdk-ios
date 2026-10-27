/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit
import Security

extension Flags {
    /// Controls optional verification of assignment responses.
    public enum ResponseSigningMode {
        /// Preserve ordinary request and cache behavior without signing work.
        case off
        /// Accept otherwise-valid assignments when verification fails. Intended for initial rollout.
        case observe
        /// Require verification; use only unexpired verified memory for fallback.
        case required
    }

    /// Explicit trust configuration for the response-signing draft.
    public struct ResponseSigningConfiguration {
        public var mode: ResponseSigningMode
        /// Locally provisioned public root certificates in DER form. Never populate from a response.
        /// No production root is bundled. Changing intermediates does not require changing these roots.
        public var trustedRootCertificates: [Data]

        public init(mode: ResponseSigningMode = .off, trustedRootCertificates: [Data] = []) {
            self.mode = mode
            self.trustedRootCertificates = trustedRootCertificates
        }
    }
}

/// Created by verification in this fetcher only. Deliberately never serialized to disk.
internal struct FlagsResponseVerification: Equatable {
    let scope: UUID
    let verifiedAt: TimeInterval
    let expiresAt: TimeInterval
    var cacheScope: String? = nil

    func isValid(at now: Date, scope: UUID) -> Bool {
        self.scope == scope && verifiedAt <= now.timeIntervalSince1970 && expiresAt > now.timeIntervalSince1970
    }
}

internal final class FlagsResponseVerifier {
    static let capability = "response-signing-v3"
    static let prefix = "x-datadog-feature-flags-"
    static let maximumResponseBytes = 2 * 1_024 * 1_024
    let scope = UUID()
    let configuration: Flags.ResponseSigningConfiguration

    init(configuration: Flags.ResponseSigningConfiguration) { self.configuration = configuration }

    /// Hash only configuration/identity, excluding nonce and subject. Subject matching is a separate repository gate.
    func cacheScope(request: URLRequest, environment: String, customHeaderNames: [String]) -> String {
        var data = Data("datadog.flags.response-signing.cache.v3\0".utf8)
        func append(_ value: Data) {
            Self.appendInteger(UInt64(value.count), to: &data)
            data.append(value)
        }
        append(Data(String(describing: configuration.mode).utf8))
        append(Data((request.url?.absoluteString ?? "").utf8))
        append(Data(environment.utf8))
        let names = Set(
            customHeaderNames.map { $0.lowercased() } + [
                "dd-client-token", "authorization", "content-type", "dd-application-id", "x-rkyv", "x-use-cache",
                "x-dd-feature-flags-capabilities"
            ]
        ).subtracting([Self.prefix + "request-nonce", Self.prefix + "signature-version"]).sorted()
        for name in names {
            append(Data(name.utf8))
            if let value = request.value(forHTTPHeaderField: name) {
                data.append(1)
                append(Data(value.trimmingCharacters(in: CharacterSet(charactersIn: " \t")).utf8))
            } else {
                data.append(0)
            }
        }
        for root in configuration.trustedRootCertificates {
            append(root)
        }
        return Self.hex(Self.digest(data))
    }

    static func cacheKey(clientName: String, scope: String) -> String {
        var data = Data(clientName.utf8)
        data.append(0)
        data.append(Data(scope.utf8))
        return "response-signing-v3-" + hex(digest(data))
    }

    func prepare(_ original: URLRequest) throws -> URLRequest {
        if configuration.mode == .required && configuration.trustedRootCertificates.isEmpty {
            throw FlagsSigningError.missingAnchor
        }
        guard configuration.trustedRootCertificates.count <= 4,
            configuration.trustedRootCertificates.allSatisfy({ !$0.isEmpty && $0.count <= 4_096 })
        else {
            throw FlagsSigningError.invalidCertificate
        }
        var request = original
        for key in [
            "dd-client-token", "authorization", "content-type", "dd-application-id", "x-rkyv", "x-use-cache",
            "x-dd-feature-flags-capabilities"
        ] {
            if let value = request.value(forHTTPHeaderField: key) {
                request.setValue(
                    value.trimmingCharacters(in: CharacterSet(charactersIn: " \t")),
                    forHTTPHeaderField: key
                )
            }
        }
        var nonce = [UInt8](repeating: 0, count: 16)
        let status = nonce.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, bytes.count, address)
        }
        guard status == errSecSuccess else {
            throw FlagsSigningError.unsupportedRequest
        }
        request.setValue("3", forHTTPHeaderField: Self.prefix + "signature-version")
        request.setValue(Self.hex(Data(nonce)), forHTTPHeaderField: Self.prefix + "request-nonce")
        let existing = (request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        request.setValue(
            Array(Set(existing + [Self.capability])).sorted().joined(separator: ","),
            forHTTPHeaderField: "x-dd-feature-flags-capabilities"
        )
        _ = try Self.requestComponents(request)
        return request
    }

    func verify(request: URLRequest, response: HTTPURLResponse, body: Data, now: Date) throws
        -> FlagsResponseVerification
    {
        _ = try Self.requestComponents(request)
        guard body.count <= Self.maximumResponseBytes else {
            throw FlagsSigningError.responseTooLarge
        }
        guard !configuration.trustedRootCertificates.isEmpty else {
            throw FlagsSigningError.missingAnchor
        }
        guard response.statusCode == 200, try Self.header(response, "signature-version") == "3" else {
            throw FlagsSigningError.invalidProof
        }
        let leafDER = try Self.base64(Self.header(response, "signing-certificate"), limit: 4_096)
        let intermediateDER = try Self.base64(Self.header(response, "signing-intermediate"), limit: 4_096)
        let identifier = try Self.header(response, "certificate-id")
        guard identifier == Self.hex(Self.digest(leafDER)) else {
            throw FlagsSigningError.invalidProof
        }
        let issuedAt = try Self.seconds(Self.header(response, "issued-at"))
        let expiresAt = try Self.seconds(Self.header(response, "expires-at"))
        let seconds = now.timeIntervalSince1970
        guard Double(issuedAt) <= seconds + 30, Double(expiresAt) > seconds,
            expiresAt > issuedAt, expiresAt - issuedAt <= 300
        else {
            throw FlagsSigningError.expiredProof
        }
        let leaf = try FlagsSigningCertificate(der: leafDER, role: .leaf)
        let intermediate = try FlagsSigningCertificate(der: intermediateDER, role: .intermediate)
        try Self.verifyChild(leaf, parent: intermediate)
        var anchored = false
        for data in configuration.trustedRootCertificates {
            guard let root = try? FlagsSigningCertificate(der: data, role: .anchor),
                (try? Self.verifyChild(intermediate, parent: root)) != nil,
                root.notBefore <= seconds, seconds < root.notAfter,
                Double(issuedAt) >= root.notBefore, Double(expiresAt) <= root.notAfter
            else { continue }
            anchored = true
            break
        }
        guard anchored else {
            throw FlagsSigningError.invalidCertificate
        }
        for certificate in [leaf, intermediate] {
            guard certificate.notBefore <= seconds, seconds < certificate.notAfter,
                Double(issuedAt) >= certificate.notBefore, Double(expiresAt) <= certificate.notAfter
            else {
                throw FlagsSigningError.expiredProof
            }
        }
        let signature = try Self.base64(Self.header(response, "signature"), limit: 72)
        let transcript = try Self.transcript(
            request: request,
            status: response.statusCode,
            body: body,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            leaf: leafDER,
            intermediate: intermediateDER
        )
        try Self.verifySignature(signature, bytes: transcript, key: leaf.publicKey)
        return FlagsResponseVerification(scope: scope, verifiedAt: seconds, expiresAt: Double(expiresAt))
    }

    static func transcript(
        request: URLRequest,
        status: Int,
        body: Data,
        issuedAt: UInt64,
        expiresAt: UInt64,
        leaf: Data,
        intermediate: Data
    ) throws -> Data {
        let components = try requestComponents(request)
        guard let status = UInt16(exactly: status), body.count <= maximumResponseBytes else {
            throw FlagsSigningError.invalidProof
        }
        var result = Data("datadog.feature-flags.precomputed-assignments.v3\0".utf8)
        for value in components { try appendLength(Data(value.utf8), to: &result) }
        guard let nonce = request.value(forHTTPHeaderField: prefix + "request-nonce") else {
            throw FlagsSigningError.unsupportedRequest
        }
        var nonceBytes = Data()
        var index = nonce.startIndex
        while index < nonce.endIndex {
            let end = nonce.index(index, offsetBy: 2)
            guard let value = UInt8(nonce[index..<end], radix: 16) else {
                throw FlagsSigningError.unsupportedRequest
            }
            nonceBytes.append(value)
            index = end
        }
        try appendLength(nonceBytes, to: &result)
        result.append(digest(request.httpBody ?? Data()))
        result.append(digest(Data((request.value(forHTTPHeaderField: "dd-client-token") ?? "").utf8)))
        for name in ["content-type", "dd-application-id", "x-rkyv", "x-use-cache", "x-dd-feature-flags-capabilities"] {
            if let value = request.value(forHTTPHeaderField: name) {
                result.append(1)
                try appendLength(Data(value.utf8), to: &result)
            } else {
                result.append(0)
            }
        }
        if let auth = request.value(forHTTPHeaderField: "authorization") {
            result.append(1)
            result.append(digest(Data(auth.utf8)))
        } else {
            result.append(0)
        }
        appendInteger(status, to: &result)
        appendInteger(issuedAt, to: &result)
        appendInteger(expiresAt, to: &result)
        appendInteger(UInt64(body.count), to: &result)
        result.append(digest(body))
        result.append(digest(leaf))
        result.append(digest(intermediate))
        return result
    }

    private static func requestComponents(_ request: URLRequest) throws -> [String] {
        guard request.httpMethod == "POST", let url = request.url,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, parts.fragment == nil,
            var host = parts.host?.lowercased(), !host.isEmpty,
            (request.httpBody?.count ?? 0) <= 1_024 * 1_024,
            request.value(forHTTPHeaderField: prefix + "signature-version") == "3",
            let nonce = request.value(forHTTPHeaderField: prefix + "request-nonce"), nonce.utf8.count == 32,
            nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let token = request.value(forHTTPHeaderField: "dd-client-token"), !token.isEmpty, !token.contains(",")
        else {
            throw FlagsSigningError.unsupportedRequest
        }
        for name in ["content-type", "dd-application-id", "x-rkyv", "x-use-cache", "authorization"] {
            if request.value(forHTTPHeaderField: name)?.contains(",") == true {
                throw FlagsSigningError.unsupportedRequest
            }
        }
        let capabilities = (request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
            .split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard capabilities.contains(capability), Set(capabilities).count == capabilities.count else {
            throw FlagsSigningError.unsupportedRequest
        }
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        if let port = parts.port, port != 443 { host += ":\(port)" }
        return [
            "POST", "https", host, parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath,
            parts.percentEncodedQuery.map { "?" + $0 } ?? ""
        ]
    }

    private static func verifyChild(_ child: FlagsSigningCertificate, parent: FlagsSigningCertificate) throws {
        try child.validateLink(to: parent)
        try verifySignature(child.signature, bytes: child.tbs, key: parent.publicKey)
    }

    private static func verifySignature(_ signature: Data, bytes: Data, key: Data) throws {
        try FlagsSigningCertificate.validateSignature(signature)
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: key),
            let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature),
            publicKey.isValidSignature(parsed, for: bytes)
        else {
            throw FlagsSigningError.invalidSignature
        }
    }

    private static func header(_ response: HTTPURLResponse, _ suffix: String) throws -> String {
        let name = prefix + suffix
        let values = response.allHeaderFields.compactMap { key, value -> String? in
            guard let key = key as? String, key.lowercased() == name else {
                return nil
            }
            return value as? String
        }
        guard values.count == 1, let value = values.first, !value.isEmpty else {
            throw FlagsSigningError.missingProof
        }
        guard value.utf8.count <= 5_464, !value.contains(",") else {
            throw FlagsSigningError.invalidProof
        }
        return value
    }

    private static func seconds(_ string: String) throws -> UInt64 {
        guard !string.isEmpty, string.utf8.count <= 16, string.utf8.allSatisfy({ (48...57).contains($0) }),
            string == "0" || !string.hasPrefix("0"), let value = UInt64(string), value <= 9_007_199_254_740_991
        else {
            throw FlagsSigningError.invalidProof
        }
        return value
    }

    private static func base64(_ value: String, limit: Int) throws -> Data {
        guard value.utf8.count <= 4 * ((limit + 2) / 3), let decoded = Data(base64Encoded: value),
            !decoded.isEmpty, decoded.count <= limit, decoded.base64EncodedString() == value
        else {
            throw FlagsSigningError.invalidProof
        }
        return decoded
    }

    private static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private static func appendLength(_ value: Data, to output: inout Data) throws {
        guard let length = UInt32(exactly: value.count) else {
            throw FlagsSigningError.invalidProof
        }
        appendInteger(length, to: &output)
        output.append(value)
    }
    private static func appendInteger<T: FixedWidthInteger>(_ value: T, to output: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }
}
