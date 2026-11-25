/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit
import Security
import DatadogInternal

extension Flags {
    /// Experimental. Response signing is in preview and works only on the Datadog staging endpoint. The API can change or be removed in a minor release, based on customer feedback.
    ///
    /// Controls optional verification of assignment responses.
    public enum ResponseSigningMode {
        /// Preserve ordinary request and cache behavior without signing work.
        case off
        /// Accept otherwise-valid assignments when verification fails. Intended for initial rollout.
        case observe
        /// Require verification. Verified flags stay in memory only; see expireVerifiedFlags for proof expiry.
        case required
    }

    /// Experimental. Response signing is in preview and works only on the Datadog staging endpoint. The API can change or be removed in a minor release, based on customer feedback.
    ///
    /// Optional response signing. Staging only; production is not supported yet.
    ///
    /// The SDK pins one built-in root: the staging root. Production support comes in a later release.
    /// For any other endpoint, `observe` has no effect: the SDK logs a warning and sends the ordinary request.
    /// For any other endpoint, `required` fails closed: the SDK logs an error, sends no assignment request,
    /// and returns `FlagsError.responseSigningFailed(reason: "unsupported-site")` on every fetch.
    public struct ResponseSigningConfiguration {
        public var mode: ResponseSigningMode
        /// Experimental. Controls what `required` mode does when the proof of the last verified response expires.
        ///
        /// - `false` (default): the client keeps serving the last verified flags, and its state changes to `stale`.
        ///   A network attacker can block refreshes and keep the flags at their last verified values.
        ///   The attacker cannot forge values. The guarantee is "verified once", not "fresh".
        /// - `true`: the client state changes to `error`, and evaluations return defaults. This is the strict guarantee.
        ///
        /// A new verified response returns the state to `ready` in both settings. `required` mode persists no flag data,
        /// so after a restart evaluations return defaults until the first verified response. No effect in `observe` or `off`.
        public var expireVerifiedFlags: Bool
        /// Test-only trust anchors in DER form. Production code never sets them, and a response never supplies them.
        internal var trustedRootCertificates: [Data]

        public init(mode: ResponseSigningMode = .off, expireVerifiedFlags: Bool = false) {
            self.init(mode: mode, trustedRootCertificates: [], expireVerifiedFlags: expireVerifiedFlags)
        }

        internal init(mode: ResponseSigningMode, trustedRootCertificates: [Data], expireVerifiedFlags: Bool = false) {
            self.mode = mode
            self.expireVerifiedFlags = expireVerifiedFlags
            self.trustedRootCertificates = trustedRootCertificates
        }

        /// The only endpoint that serves signed assignments: the staging (`datad0g.com`) assignment edge.
        /// `DatadogSite` has no staging case, so staging is selected with `customFlagsEndpoint`.
        internal static func isStagingEndpoint(_ endpoint: URL?) -> Bool {
            guard let endpoint = endpoint,
                let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
                parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "preview.ff-cdn.datad0g.com",
                parts.port == nil || parts.port == 443, parts.user == nil, parts.password == nil
            else {
                return false
            }
            return true
        }

        /// Returns the configuration that the feature applies to `customFlagsEndpoint`.
        /// Outside staging, `observe` is a no-op: the result is `off`, so requests and responses stay unchanged.
        /// Outside staging, `required` stays `required`. No root applies, so every fetch fails closed before a request.
        internal func effective(customFlagsEndpoint: URL?) -> ResponseSigningConfiguration {
            guard mode != .off, !Self.isStagingEndpoint(customFlagsEndpoint) else {
                return self
            }
            if mode == .required {
                DD.logger.error(
                    """
                    Flags response signing is supported only on the Datadog staging endpoint \
                    `https://preview.ff-cdn.datad0g.com` in this SDK version. Production support comes in a later release. \
                    The `required` mode fails closed: the SDK sends no assignment request and evaluations return defaults. \
                    Remove `required`, or use `observe`.
                    """
                )
                return self
            }
            DD.logger.warn(
                """
                Flags response signing is supported only on the Datadog staging endpoint \
                `https://preview.ff-cdn.datad0g.com` in this SDK version. Production support comes in a later release. \
                Response signing is disabled for this configuration, and flags are not verified.
                """
            )
            return ResponseSigningConfiguration()
        }

        internal func roots(for endpoint: URL?) -> [Data] {
            if !trustedRootCertificates.isEmpty {
                return trustedRootCertificates
            }
            return Self.isStagingEndpoint(endpoint) ? [Self.stagingRoot] : []
        }

        /// `CN=Datadog Customer Signing Root CA - staging`, the only built-in anchor.
        /// SHA-256 of the DER: `0e469f3cecc9cd51fd64373879636540512d56e99eecd70361c78b98c47ea934`.
        /// Subject key identifier: `aa5e91e52cdb130d175eed1010a501c0ef45d60d`. Valid until 2036-11-16.
        /// Leaf and intermediate certificates rotate on the server and are never pinned.
        internal static let stagingRoot: Data = {
            let base64 =
                "MIIB0TCCAXigAwIBAgIUeuKLTmp+6/G7at2Gdr8kEvQXr+MwCgYIKoZIzj0EAwIwNTEzMDEGA1UEAxMqRGF0YWRvZyBDdXN0b21l" +
                "ciBTaWduaW5nIFJvb3QgQ0EgLSBzdGFnaW5nMB4XDTI2MTExOTIzNTYzOVoXDTM2MTExNjIzNTcwOVowNTEzMDEGA1UEAxMqRGF0" +
                "YWRvZyBDdXN0b21lciBTaWduaW5nIFJvb3QgQ0EgLSBzdGFnaW5nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEnqgqgmas0ot4" +
                "6nCUq418zkd+SCG5EzGmtxKAFSAT4rGTtmylNee/9Asw5nKeV5eLN5Ki7zZ/3wBgIBL/owvov6NmMGQwDgYDVR0PAQH/BAQDAgEG" +
                "MBIGA1UdEwEB/wQIMAYBAf8CAQIwHQYDVR0OBBYEFKpekeUs2xMNF17tEBClAcDvRdYNMB8GA1UdIwQYMBaAFKpekeUs2xMNF17t" +
                "EBClAcDvRdYNMAoGCCqGSM49BAMCA0cAMEQCIC6R3Cx6TgUbrKOr+jG2wvrbmNLt97tVUqEOne3nKrdtAiAXfSsjQefOVfiEFg+5" +
                "G3ksGZzZTkfOPxf0Zl1WOqmrgA=="
            // swiftlint:disable:next force_unwrapping
            return Data(base64Encoded: base64)!
        }()
    }
}

/// Created by verification in this fetcher only. Deliberately never serialized to disk.
internal struct FlagsResponseVerification: Equatable {
    let scope: UUID
    let verifiedAt: TimeInterval
    let expiresAt: TimeInterval
    var cacheScope: String? = nil
    /// The verified response carried a minimum leaf not-before value that the SDK ignored.
    var ignoredMinimumNotBefore = false
    /// The response headers that the signed response list names, with their verified values. `nil` is an absent header.
    /// The SDK acts on these values only, never on a second read of the raw response headers.
    var verifiedResponseHeaders: [String: String?] = [:]

    func verifiedResponseHeader(_ name: String) -> String? {
        verifiedResponseHeaders[name] ?? nil
    }

    /// `allowExpired` keeps a proof usable after `expiresAt`: it was verified once in this scope, but it is not fresh.
    /// The largest backward clock step after verification that keeps the proof fresh, like the `issued-at` allowance.
    static let backwardClockTolerance: TimeInterval = 30

    /// A proof is fresh from `verifiedAt` (less a 30 s backward clock step) until `expiresAt`.
    /// A larger backward step is handled as expiry: `allowExpired` keeps the proof usable as not fresh.
    func isValid(at now: Date, scope: UUID, allowExpired: Bool = false) -> Bool {
        let seconds = now.timeIntervalSince1970
        let fresh = verifiedAt - Self.backwardClockTolerance <= seconds && expiresAt > seconds
        return self.scope == scope && (allowExpired || fresh)
    }
}

/// DRAFT wire. Persists the highest accepted minimum leaf not-before value (the leaf floor) per trust anchor.
/// This is the only data that `required` mode persists. It holds no flag data.
internal protocol FlagsMinimumNotBeforeStore: AnyObject {
    /// `waitForRead` waits for the first persistent read with no time limit, so the floor is never skipped.
    func value(forAnchor anchor: String, waitForRead: Bool) -> UInt64?
    func store(_ value: UInt64, forAnchor anchor: String)
}

/// Keeps values in memory only. The verifier uses it when no persistent store is given.
internal final class InMemoryMinimumNotBeforeStore: FlagsMinimumNotBeforeStore {
    @ReadWriteLock
    private var values: [String: UInt64] = [:]

    func value(forAnchor anchor: String, waitForRead: Bool) -> UInt64? { values[anchor] }

    func store(_ value: UInt64, forAnchor anchor: String) {
        _values.mutate { $0[anchor] = max($0[anchor] ?? 0, value) }
    }
}

/// Persists values in the Flags feature data store, so they survive a restart.
internal final class DataStoreMinimumNotBeforeStore: FlagsMinimumNotBeforeStore {
    static let keyPrefix = "response-signing-minimum-leaf-not-before-"
    private let dataStore: any DataStore
    private let readTimeout: TimeInterval
    private let lock = NSLock()
    /// Anchors that were read from disk or written, with their value. `nil` means "read, no value".
    private var values: [String: UInt64?] = [:]

    init(dataStore: any DataStore, readTimeout: TimeInterval = 0.5) {
        self.dataStore = dataStore
        self.readTimeout = readTimeout
    }

    func value(forAnchor anchor: String, waitForRead: Bool) -> UInt64? {
        lock.lock()
        if let cached = values[anchor] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        // Verification runs on the assignment fetch queue, never on the data store queue, so waiting is safe.
        // `required` waits for the read: it must never skip the floor. `observe` waits a short time.
        let group = DispatchGroup()
        group.enter()
        var read: UInt64??
        dataStore.value(forKey: Self.keyPrefix + anchor) { [lock] result in
            let value = result.data().flatMap { String(data: $0, encoding: .utf8) }.flatMap(UInt64.init)
            lock.lock()
            read = .some(value)
            lock.unlock()
            group.leave()
        }
        if waitForRead {
            group.wait()
        } else {
            _ = group.wait(timeout: .now() + readTimeout)
        }
        lock.lock()
        defer { lock.unlock() }
        guard let read else {
            // `observe` only: the read did not finish in time. Try again on the next verification.
            return values[anchor] ?? nil
        }
        let merged = [values[anchor] ?? nil, read].compactMap { $0 }.max()
        values[anchor] = .some(merged)
        return merged
    }

    func store(_ value: UInt64, forAnchor anchor: String) {
        lock.lock()
        defer { lock.unlock() }
        // Keep the highest value: a lower value never replaces a stored one.
        if let stored = values[anchor] ?? nil, stored >= value {
            return
        }
        values[anchor] = .some(value)
        dataStore.setValue(Data(String(value).utf8), forKey: Self.keyPrefix + anchor, version: dataStoreDefaultKeyVersion)
    }
}

internal final class FlagsResponseVerifier {
    static let capability = "response-signing-v1"
    static let signatureVersion = "1"
    static let transcriptDomain = "datadog.feature-flags.precomputed-assignments.v1\0"
    static let maximumIntermediates = 3
    static let prefix = "x-datadog-feature-flags-"
    static let maximumResponseBytes = 2 * 1_024 * 1_024
    /// The request header that names the request headers that the transcript binds.
    static let signedHeadersName = prefix + "signed-headers"
    /// Request headers that can change a signed response (the edge `bound` class). When present, each one must be
    /// in the signed request list. `x-use-cache` is a staging header: the SDK does not list it, so it is not signed.
    static let boundRequestHeaders = ["content-type", "dd-application-id", "x-dd-feature-flags-capabilities", "x-rkyv"]
    /// The proof headers. The signed response list must not name one of them.
    static let proofHeaders = [
        "signature-version", "certificate-id", "signing-certificate", "signing-chain", "issued-at", "expires-at",
        "signature", "signed-response-headers"
    ].map { prefix + $0 }
    static let flagSelectionIgnoredHeader = "dd-flag-selection-ignored"
    let scope = UUID()
    let configuration: Flags.ResponseSigningConfiguration
    let minimumNotBeforeStore: any FlagsMinimumNotBeforeStore
    /// The configured and bundled roots, parsed once instead of on each verification.
    private let parsedRoots: [Data: FlagsSigningCertificate]

    init(
        configuration: Flags.ResponseSigningConfiguration,
        minimumNotBeforeStore: any FlagsMinimumNotBeforeStore = InMemoryMinimumNotBeforeStore()
    ) {
        self.configuration = configuration
        self.minimumNotBeforeStore = minimumNotBeforeStore
        var parsedRoots: [Data: FlagsSigningCertificate] = [:]
        for data in configuration.trustedRootCertificates + [Flags.ResponseSigningConfiguration.stagingRoot] {
            parsedRoots[data] = try? FlagsSigningCertificate(der: data, role: .anchor)
        }
        self.parsedRoots = parsedRoots
    }

    /// Hash only configuration/identity, excluding nonce and subject. Subject matching is a separate repository gate.
    func cacheScope(
        request: URLRequest,
        environment: String,
        customHeaderNames: [String],
        flagSelection: CanonicalFlagSelection? = nil
    ) -> String {
        var data = Data("datadog.flags.response-signing.cache.v1\0".utf8)
        func append(_ value: Data) {
            Self.appendInteger(UInt64(value.count), to: &data)
            data.append(value)
        }
        append(Data(String(describing: configuration.mode).utf8))
        append(Data((request.url?.absoluteString ?? "").utf8))
        append(Data(environment.utf8))
        data.append(flagSelection == nil ? 0 : 1)
        if let flagSelection {
            for values in [flagSelection.tags, flagSelection.keyPatterns] {
                Self.appendInteger(UInt64(values.count), to: &data)
                for value in values { append(Data(value.utf8)) }
            }
        }
        // The RUM application ID is not in the scope: RUM can start, stop or change during a session.
        // Each response transcript still binds `dd-application-id`.
        let names = Set(
            customHeaderNames.map { $0.lowercased() } + [
                "dd-client-token", "authorization", "content-type", "x-rkyv", "x-use-cache",
                "x-dd-feature-flags-capabilities"
            ]
        ).subtracting([Self.prefix + "request-nonce", Self.prefix + "signature-version", "dd-application-id"]).sorted()
        for name in names {
            append(Data(name.utf8))
            if let value = request.value(forHTTPHeaderField: name) {
                data.append(1)
                append(Data(value.trimmingCharacters(in: CharacterSet(charactersIn: " \t")).utf8))
            } else {
                data.append(0)
            }
        }
        for root in configuration.roots(for: request.url) {
            append(root)
        }
        return Self.hex(Self.digest(data))
    }

    static func cacheKey(clientName: String) -> String {
        // Keep one observe entry per client. The encoded entry carries its trust scope.
        "response-signing-v1-observe-" + hex(digest(Data(clientName.utf8)))
    }

    func prepare(_ original: URLRequest) throws -> URLRequest {
        let roots = configuration.roots(for: original.url)
        if configuration.mode == .required && roots.isEmpty {
            // Only the staging endpoint has a built-in root.
            throw FlagsSigningError.unsupportedSite
        }
        guard roots.count <= 4,
            roots.allSatisfy({ !$0.isEmpty && $0.count <= 4_096 })
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
            throw FlagsSigningError.unavailableCrypto
        }
        request.setValue(Self.signatureVersion, forHTTPHeaderField: Self.prefix + "signature-version")
        request.setValue(Self.hex(Data(nonce)), forHTTPHeaderField: Self.prefix + "request-nonce")
        let existing = (request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        request.setValue(
            Array(Set(existing + [Self.capability])).sorted().joined(separator: ","),
            forHTTPHeaderField: "x-dd-feature-flags-capabilities"
        )
        // The SDK lists each bound header that it set. The list is already in ascending byte order.
        request.setValue(
            Self.boundRequestHeaders.filter { request.value(forHTTPHeaderField: $0) != nil }.joined(separator: ","),
            forHTTPHeaderField: Self.signedHeadersName
        )
        _ = try Self.requestComponents(request)
        return request
    }

    func verify(request: URLRequest, response: HTTPURLResponse, body: Data, now: Date) throws
        -> FlagsResponseVerification {
        _ = try Self.requestComponents(request)
        guard body.count <= Self.maximumResponseBytes else {
            throw FlagsSigningError.responseTooLarge
        }
        let roots = configuration.roots(for: request.url)
        guard !roots.isEmpty else {
            throw FlagsSigningError.missingAnchor
        }
        guard response.statusCode == 200, try Self.header(response, "signature-version") == Self.signatureVersion else {
            throw FlagsSigningError.invalidProof
        }
        let leafDER = try Self.base64(Self.header(response, "signing-certificate"), limit: 4_096)
        let intermediateDERs = try Self.chain(response)
        let identifier = try Self.header(response, "certificate-id")
        guard identifier == Self.hex(Self.digest(leafDER)) else {
            throw FlagsSigningError.invalidProof
        }
        let responseHeaders = try Self.signedResponseHeaders(response, request: request)
        let issuedAt = try Self.seconds(Self.header(response, "issued-at"))
        let expiresAt = try Self.seconds(Self.header(response, "expires-at"))
        // DRAFT wire: optional, and bound in the transcript when present.
        let minimumNotBefore = try Self.optionalHeader(response, "minimum-leaf-not-before").map(Self.seconds)
        let seconds = now.timeIntervalSince1970
        guard Double(issuedAt) <= seconds + 30, Double(expiresAt) > seconds,
            expiresAt > issuedAt, expiresAt - issuedAt <= 300
        else {
            throw FlagsSigningError.expiredProof
        }
        let leaf = try FlagsSigningCertificate(der: leafDER, role: .leaf)
        let intermediates = try intermediateDERs.map { try FlagsSigningCertificate(der: $0, role: .intermediate) }
        // Path: leaf -> intermediate[0] -> ... -> intermediate[n-1] -> pinned root.
        var child = leaf
        for (index, intermediate) in intermediates.enumerated() {
            guard let pathLength = intermediate.pathLength, pathLength >= index else {
                throw FlagsSigningError.invalidCertificate
            }
            try Self.verifyChild(child, parent: intermediate)
            child = intermediate
        }
        guard let last = intermediates.last else {
            throw FlagsSigningError.invalidProof
        }
        var anchor: Data?
        for data in roots {
            guard let root = parsedRoots[data],
                root.pathLength.map({ $0 >= intermediates.count }) ?? true,
                (try? Self.verifyChild(last, parent: root)) != nil,
                root.notBefore <= seconds, seconds < root.notAfter,
                Double(issuedAt) >= root.notBefore, Double(expiresAt) <= root.notAfter
            else { continue }
            anchor = data
            break
        }
        guard let anchor else {
            throw FlagsSigningError.invalidCertificate
        }
        for certificate in [leaf] + intermediates {
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
            intermediates: intermediateDERs,
            responseHeaders: responseHeaders,
            minimumNotBefore: minimumNotBefore
        )
        do {
            try Self.verifySignature(signature, bytes: transcript, key: leaf.publicKey)
        } catch FlagsSigningError.invalidCertificate {
            // The signature header is not a strict DER ECDSA signature: a malformed proof, not a chain failure.
            throw FlagsSigningError.invalidProof
        }
        // The floor applies to the leaf only. It is never compared with an intermediate.
        let anchorKey = Self.hex(Self.digest(anchor))
        if let stored = minimumNotBeforeStore.value(forAnchor: anchorKey, waitForRead: configuration.mode == .required),
            leaf.notBefore < Double(stored) {
            throw FlagsSigningError.revokedCertificate
        }
        var verification = FlagsResponseVerification(scope: scope, verifiedAt: seconds, expiresAt: Double(expiresAt))
        for (name, value) in responseHeaders {
            verification.verifiedResponseHeaders[name] = .some(value)
        }
        if let minimumNotBefore {
            // A response must never revoke its own leaf.
            if Double(minimumNotBefore) > leaf.notBefore {
                verification.ignoredMinimumNotBefore = true
            } else {
                minimumNotBeforeStore.store(minimumNotBefore, forAnchor: anchorKey)
            }
        }
        return verification
    }

    static func transcript(
        request: URLRequest,
        status: Int,
        body: Data,
        issuedAt: UInt64,
        expiresAt: UInt64,
        leaf: Data,
        intermediates: [Data],
        responseHeaders: [(name: String, value: String?)],
        minimumNotBefore: UInt64? = nil
    ) throws -> Data {
        let (components, signedHeaders) = try requestComponents(request)
        guard let status = UInt16(exactly: status), body.count <= maximumResponseBytes,
            (1...maximumIntermediates).contains(intermediates.count)
        else {
            throw FlagsSigningError.invalidProof
        }
        var result = Data(transcriptDomain.utf8)
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
        try appendList(signedHeaders.map { ($0, request.value(forHTTPHeaderField: $0)) }, to: &result)
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
        result.append(UInt8(intermediates.count))
        for intermediate in intermediates { result.append(digest(intermediate)) }
        try appendList(responseHeaders, to: &result)
        // DRAFT wire: absent keeps the v1 transcript unchanged. The tail stays the last field.
        if let minimumNotBefore {
            result.append(1)
            appendInteger(minimumNotBefore, to: &result)
        }
        return result
    }

    /// Returns the URL components of the transcript and the names of the signed request list.
    private static func requestComponents(_ request: URLRequest) throws -> (components: [String], signedHeaders: [String]) {
        guard request.httpMethod == "POST", let url = request.url,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(), scheme == "https",
            parts.user == nil, parts.password == nil, parts.fragment == nil,
            var host = parts.host?.lowercased(), !host.isEmpty,
            (request.httpBody?.count ?? 0) <= 1_024 * 1_024,
            request.value(forHTTPHeaderField: prefix + "signature-version") == signatureVersion,
            let nonce = request.value(forHTTPHeaderField: prefix + "request-nonce"), nonce.utf8.count == 32,
            nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let token = request.value(forHTTPHeaderField: "dd-client-token"), !token.isEmpty, !token.contains(",")
        else {
            throw FlagsSigningError.unsupportedRequest
        }
        // `URLRequest` joins repeated lines with ",". Only the capabilities value can contain a comma,
        // so a comma in another listed or bound value is a repeated line.
        guard let list = request.value(forHTTPHeaderField: signedHeadersName), let signedHeaders = headerList(list),
            signedHeaders.contains("content-type"), signedHeaders.contains("x-dd-feature-flags-capabilities"),
            !signedHeaders.contains(where: { $0 == "dd-client-token" || $0 == "authorization" || $0.hasPrefix(prefix) }),
            boundRequestHeaders.allSatisfy({ signedHeaders.contains($0) || request.value(forHTTPHeaderField: $0) == nil }),
            signedHeaders.allSatisfy({ name in
                request.value(forHTTPHeaderField: name)
                    .map { name == "x-dd-feature-flags-capabilities" || !$0.contains(",") } ?? false
            }),
            request.value(forHTTPHeaderField: "authorization")?.contains(",") != true
        else {
            throw FlagsSigningError.unsupportedRequest
        }
        let capabilities = (request.value(forHTTPHeaderField: "x-dd-feature-flags-capabilities") ?? "")
            .split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard capabilities.contains(capability), Set(capabilities).count == capabilities.count else {
            throw FlagsSigningError.unsupportedRequest
        }
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        // The authority omits the default port of the scheme.
        if let port = parts.port, port != defaultPort(scheme) { host += ":\(port)" }
        let components = [
            "POST", scheme, host, parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath,
            parts.percentEncodedQuery.map { "?" + $0 } ?? ""
        ]
        return (components, signedHeaders)
    }

    /// Parses a signed header list: 1 to 32 lowercase token names of at most 64 bytes, in ascending byte order
    /// (so unique), joined by "," with no spaces. Returns `nil` for a malformed list.
    private static func headerList(_ value: String) -> [String]? {
        let names = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let tokenBytes = Set("0123456789abcdefghijklmnopqrstuvwxyz!#$%&'*+.^_`|~-".utf8)
        guard (1...32).contains(names.count),
            names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 && $0.utf8.allSatisfy(tokenBytes.contains) }),
            zip(names, names.dropFirst()).allSatisfy({ $0.utf8.lexicographicallyPrecedes($1.utf8) })
        else {
            return nil
        }
        return names
    }

    /// The names of the signed response list in list order, with the value of each response header.
    /// The list contains commas, so it is read without `header()`.
    private static func signedResponseHeaders(
        _ response: HTTPURLResponse,
        request: URLRequest
    ) throws -> [(name: String, value: String?)] {
        guard let names = headerList(try singleHeader(response, "signed-response-headers")),
            names.contains("content-type"),
            !hasFlagSelection(request) || names.contains(flagSelectionIgnoredHeader),
            !names.contains(where: proofHeaders.contains)
        else {
            throw FlagsSigningError.invalidProof
        }
        return try names.map { name in
            let values = response.allHeaderFields.compactMap { key, value -> String? in
                (key as? String)?.lowercased() == name ? value as? String : nil
            }
            // `HTTPURLResponse` joins repeated lines with ", ". These values never contain a comma,
            // so a comma is a repeated line. A repeated line of another listed header fails the signature.
            guard values.count <= 1,
                !(name == "content-type" || name == flagSelectionIgnoredHeader) || values.first?.contains(",") != true
            else {
                throw FlagsSigningError.invalidProof
            }
            return (name, values.first)
        }
    }

    /// A request has a flag selection when its JSON body has a non-null `flag_selection` at the top level or in `data.attributes`,
    /// or its URL query has `selected_flag_tags` or `selected_flag_key_patterns`.
    private static func hasFlagSelection(_ request: URLRequest) -> Bool {
        let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        if query.contains(where: { $0.name == "selected_flag_tags" || $0.name == "selected_flag_key_patterns" }) {
            return true
        }
        // The SDK request puts the selection at `data.attributes.flag_selection`. The shared fixtures use a flat body.
        guard let body = request.httpBody,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let selection = object["flag_selection"]
                ?? ((object["data"] as? [String: Any])?["attributes"] as? [String: Any])?["flag_selection"]
        else {
            return false
        }
        return !(selection is NSNull)
    }

    private static func defaultPort(_ scheme: String) -> Int { scheme == "https" ? 443 : 80 }

    /// Intermediates in issuance order: index 0 issued the leaf, and a pinned root issued the last one.
    /// The header joins 1 to 3 standard base64 DER entries with "," and no spaces.
    private static func chain(_ response: HTTPURLResponse) throws -> [Data] {
        let value = try singleHeader(response, "signing-chain")
        let entries = value.split(separator: ",", omittingEmptySubsequences: false)
        guard value.utf8.count <= maximumIntermediates * 5_465 - 1,
            (1...maximumIntermediates).contains(entries.count)
        else {
            throw FlagsSigningError.invalidProof
        }
        return try entries.map { try base64(String($0), limit: 4_096) }
    }

    static func verifyChild(_ child: FlagsSigningCertificate, parent: FlagsSigningCertificate) throws {
        try child.validateLink(to: parent)
        do {
            try verifySignature(child.signature, bytes: child.tbs, key: parent.publicKey)
        } catch FlagsSigningError.invalidSignature {
            // A certificate that its issuer did not sign is a chain failure, as in the browser verifier.
            throw FlagsSigningError.invalidCertificate
        }
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
        let value = try singleHeader(response, suffix)
        guard value.utf8.count <= 5_464, !value.contains(",") else {
            throw FlagsSigningError.invalidProof
        }
        return value
    }

    private static func optionalHeader(_ response: HTTPURLResponse, _ suffix: String) throws -> String? {
        let name = prefix + suffix
        guard response.allHeaderFields.keys.contains(where: { ($0 as? String)?.lowercased() == name }) else {
            return nil
        }
        return try header(response, suffix)
    }

    private static func singleHeader(_ response: HTTPURLResponse, _ suffix: String) throws -> String {
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
    /// `u8(count) || for each name: lp(name) || u8(presence) || lp(value)`. An absent header has an empty value.
    private static func appendList(_ entries: [(name: String, value: String?)], to output: inout Data) throws {
        guard let count = UInt8(exactly: entries.count) else {
            throw FlagsSigningError.invalidProof
        }
        output.append(count)
        for (name, value) in entries {
            try appendLength(Data(name.utf8), to: &output)
            output.append(value == nil ? 0 : 1)
            try appendLength(Data((value ?? "").utf8), to: &output)
        }
    }
    private static func appendInteger<T: FixedWidthInteger>(_ value: T, to output: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }
}
