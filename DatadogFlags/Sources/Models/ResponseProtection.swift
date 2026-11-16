/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation
import DatadogInternal

extension Flags {
    /// Protects the flag assignments that the SDK fetches from tampering in transit.
    ///
    /// The application selects the protection method locally. A server response cannot select a weaker method,
    /// another endpoint, or other trust material. The protection applies only to flag assignment requests.
    /// It does not change other SDK uploads, such as RUM, Logs, exposures, or evaluations.
    ///
    /// ```swift
    /// var configuration = Flags.Configuration()
    /// configuration.responseProtection = .tlsPinning(
    ///     mode: .required,
    ///     profile: .datadogStagingV1
    /// )
    /// Flags.enable(with: configuration)
    /// ```
    public enum ResponseProtection: Sendable {
        /// Requires normal TLS validation and a pinned server public key on every assignment connection.
        ///
        /// The SDK first runs the default system trust evaluation (certificate chain, hostname, and validity time).
        /// It then requires the SHA-256 hash of the leaf certificate's DER `SubjectPublicKeyInfo` to match one pin
        /// of `profile`. If a check fails, the SDK cancels the connection before it sends the request.
        ///
        /// Assignments are fetched only from the origin of `profile`. When ``Flags/Configuration/customFlagsEndpoint``
        /// is set, it must use the same origin. Assignments cached without the same protection are not loaded.
        ///
        /// If `profile` is invalid, the SDK logs an error and rejects all new assignments. Evaluations then return
        /// the default values.
        ///
        /// - Parameters:
        ///   - mode: The enforcement mode.
        ///   - profile: The endpoint and the public key pins to trust.
        case tlsPinning(mode: TLSPinningMode, profile: TLSPinPolicy)
    }
}

extension Flags.ResponseProtection {
    /// The enforcement mode of ``Flags/ResponseProtection/tlsPinning(mode:profile:)``.
    public enum TLSPinningMode: Sendable {
        /// Rejects new assignments unless the TLS connection passes system trust evaluation and matches a pin.
        case required
    }

    /// An exact HTTPS origin and the public key pins that the SDK trusts for it.
    ///
    /// A pin is the base64-encoded SHA-256 hash of the DER-encoded `SubjectPublicKeyInfo` of a leaf certificate.
    /// You can compute a pin with this command:
    ///
    /// ```
    /// openssl x509 -in leaf.pem -pubkey -noout \
    ///   | openssl pkey -pubin -outform DER \
    ///   | openssl dgst -sha256 -binary | base64
    /// ```
    ///
    /// A policy needs at least two different pins: the active key and a backup key. The backup key lets the
    /// server rotate its key without a new application release. The SDK validates the policy when the Flags
    /// feature is enabled.
    public struct TLSPinPolicy: Sendable {
        /// The exact HTTPS origin, for example `https://flags.example.com`.
        ///
        /// The origin must use the `https` scheme and must not contain a path, query, fragment, or credentials.
        /// Only this host and port are trusted. Subdomains and redirects to other origins are rejected.
        public let origin: URL

        /// The base64-encoded SHA-256 hashes of the trusted leaf `SubjectPublicKeyInfo` structures.
        public let spkiSHA256Pins: Set<String>

        /// `true` for bundled profiles whose pins are not reviewed yet.
        internal let isPlaceholder: Bool

        /// Creates a custom pin policy.
        ///
        /// - Parameters:
        ///   - origin: The exact HTTPS origin that serves flag assignments.
        ///   - spkiSHA256Pins: At least two base64-encoded SHA-256 hashes of leaf `SubjectPublicKeyInfo` structures.
        public init(origin: URL, spkiSHA256Pins: Set<String>) {
            self.init(origin: origin, spkiSHA256Pins: spkiSHA256Pins, isPlaceholder: false)
        }

        internal init(origin: URL, spkiSHA256Pins: Set<String>, isPlaceholder: Bool) {
            self.origin = origin
            self.spkiSHA256Pins = spkiSHA256Pins
            self.isPlaceholder = isPlaceholder
        }

        /// The Datadog staging profile, version 1.
        ///
        /// - Warning: This profile is a placeholder. Its hostname is not provisioned and its pins are not reviewed
        ///   public keys. All assignment requests fail with this profile until a reviewed policy replaces it.
        public static var datadogStagingV1: TLSPinPolicy {
            stagingV1
        }

        private static let stagingV1 = TLSPinPolicy(
            // swiftlint:disable:next force_unwrapping
            origin: URL(string: "https://ff-cdn-pinning-staging.datad0g.com")!,
            spkiSHA256Pins: [
                // UNVERIFIED PLACEHOLDER: SHA-256 of "dd-sdk-ios flags datadogStagingV1 placeholder active pin".
                "pmw1sCrkXoU6R0fBNRTC4cmJ9IJxlgGp27ntnGOLdU8=",
                // UNVERIFIED PLACEHOLDER: SHA-256 of "dd-sdk-ios flags datadogStagingV1 placeholder backup pin".
                "sNsnJM/AghYI5SHTLunQQ2rcLRMmH3hwDxvmM189iZM=",
            ],
            isPlaceholder: true
        )
    }
}

// MARK: - Validated policy

/// The response protection that the SDK enforces, validated from ``Flags/ResponseProtection``.
internal enum ResponseProtectionPolicy: Equatable {
    case tlsPinning(ResolvedTLSPinPolicy)
    /// The application requires protection, but its configuration is invalid. Every assignment request fails.
    case misconfigured

    /// Identifies the policy in persisted assignments. Assignments persisted under another policy are not loaded.
    var cacheIdentifier: String {
        switch self {
        case .tlsPinning(let policy): return policy.cacheIdentifier
        case .misconfigured: return "misconfigured"
        }
    }

    /// Validates the configured protection. Returns `nil` when no protection is configured.
    static func resolve(
        _ protection: Flags.ResponseProtection?,
        customFlagsEndpoint: URL?,
        telemetry: Telemetry
    ) -> ResponseProtectionPolicy? {
        switch make(from: protection, customFlagsEndpoint: customFlagsEndpoint) {
        case .success(let policy):
            if case .tlsPinning(let resolved)? = policy, resolved.isPlaceholder {
                let message = """
                `Flags.Configuration.responseProtection` uses a profile with unverified placeholder pins. \
                Assignment requests will fail until a reviewed profile is available.
                """
                DD.logger.warn(message)
                consolePrint(message, .warn)
            }
            return policy
        case .failure(let error):
            let message = "`Flags.Configuration.responseProtection` is invalid: \(error.description) New flag assignments will be rejected."
            DD.logger.error(message)
            consolePrint(message, .error)
            telemetry.debug("Response protection rejected", attributes: ["reason": error.reason])
            return .misconfigured
        }
    }

    static func make(
        from protection: Flags.ResponseProtection?,
        customFlagsEndpoint: URL?
    ) -> Result<ResponseProtectionPolicy?, ResponseProtectionConfigurationError> {
        guard let protection else {
            return .success(nil)
        }
        switch protection {
        case let .tlsPinning(mode: .required, profile: profile):
            return ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: customFlagsEndpoint)
                .map { .tlsPinning($0) }
        }
    }
}

internal enum ResponseProtectionConfigurationError: Error, Equatable {
    case originIsNotHTTPS
    case originHasNoHost
    case originIsNotExact
    case invalidPin
    case notEnoughPins(minimum: Int)
    case customEndpointOutsidePolicy

    /// A short value for telemetry. It never contains configured values.
    var reason: String {
        switch self {
        case .originIsNotHTTPS: return "origin_not_https"
        case .originHasNoHost: return "origin_no_host"
        case .originIsNotExact: return "origin_not_exact"
        case .invalidPin: return "invalid_pin"
        case .notEnoughPins: return "not_enough_pins"
        case .customEndpointOutsidePolicy: return "custom_endpoint_outside_policy"
        }
    }

    var description: String {
        switch self {
        case .originIsNotHTTPS:
            return "The pin policy origin must use the `https` scheme."
        case .originHasNoHost:
            return "The pin policy origin must have a host."
        case .originIsNotExact:
            return "The pin policy origin must not contain a path, query, fragment, or credentials."
        case .invalidPin:
            return "Each pin must be a base64-encoded SHA-256 hash (32 bytes)."
        case .notEnoughPins(let minimum):
            return "The pin policy must contain at least \(minimum) different pins (active and backup)."
        case .customEndpointOutsidePolicy:
            return "`Flags.Configuration.customFlagsEndpoint` must use the origin of the pin policy."
        }
    }
}

/// A validated ``Flags/ResponseProtection/TLSPinPolicy``.
internal struct ResolvedTLSPinPolicy: Equatable {
    static let minimumPinCount = 2
    private static let defaultHTTPSPort = 443

    /// The lowercased host name.
    let host: String
    let port: Int
    /// Canonical base64 encodings of 32-byte SHA-256 hashes.
    let pins: Set<String>
    /// The URL of the flag assignments request.
    let assignmentsURL: URL
    let isPlaceholder: Bool

    var cacheIdentifier: String {
        let canonical = "tls-pinning;required;https://\(host):\(port);" + pins.sorted().joined(separator: ",")
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "tls-pinning-v1:\(digest)"
    }

    func permits(host: String, port: Int) -> Bool {
        host.lowercased() == self.host && port == self.port
    }

    func permits(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host else {
            return false
        }
        return permits(host: host, port: url.port ?? Self.defaultHTTPSPort)
    }

    static func make(
        from profile: Flags.ResponseProtection.TLSPinPolicy,
        customFlagsEndpoint: URL?
    ) -> Result<ResolvedTLSPinPolicy, ResponseProtectionConfigurationError> {
        guard let components = URLComponents(url: profile.origin, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https" else {
            return .failure(.originIsNotHTTPS)
        }
        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return .failure(.originHasNoHost)
        }
        guard components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            return .failure(.originIsNotExact)
        }
        let port = components.port ?? defaultHTTPSPort

        var pins: Set<String> = []
        for pin in profile.spkiSHA256Pins {
            guard let hash = Data(base64Encoded: pin), hash.count == SHA256.byteCount else {
                return .failure(.invalidPin)
            }
            pins.insert(hash.base64EncodedString())
        }
        guard pins.count >= minimumPinCount else {
            return .failure(.notEnoughPins(minimum: minimumPinCount))
        }

        var policy = ResolvedTLSPinPolicy(
            host: host,
            port: port,
            pins: pins,
            assignmentsURL: profile.origin,
            isPlaceholder: profile.isPlaceholder
        )
        if let customFlagsEndpoint {
            // A custom endpoint needs its own explicit policy; it never inherits trust from another origin.
            guard policy.permits(url: customFlagsEndpoint) else {
                return .failure(.customEndpointOutsidePolicy)
            }
            policy = policy.with(assignmentsURL: customFlagsEndpoint)
        } else {
            var url = components
            url.path = "/precompute-assignments"
            guard let assignmentsURL = url.url else {
                return .failure(.originIsNotExact)
            }
            policy = policy.with(assignmentsURL: assignmentsURL)
        }
        return .success(policy)
    }

    private func with(assignmentsURL: URL) -> ResolvedTLSPinPolicy {
        ResolvedTLSPinPolicy(host: host, port: port, pins: pins, assignmentsURL: assignmentsURL, isPlaceholder: isPlaceholder)
    }
}
