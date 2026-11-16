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
    ///
    /// More protection methods may be added in a minor version. A `switch` over this type needs `@unknown default`.
    public enum ResponseProtection: Sendable {
        /// Requires normal TLS validation and a pinned public key on every assignment connection.
        ///
        /// The SDK first runs the default system trust evaluation (certificate chain, hostname, and validity time).
        /// It then requires the SHA-256 hash of a DER `SubjectPublicKeyInfo` in the validated chain to match one pin
        /// of `profile`. The ``TLSPinPolicy/pinTarget`` selects which certificates count. If a check fails, the SDK
        /// cancels the connection before it sends the request.
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
    ///
    /// More modes may be added in a minor version. A `switch` over this type needs `@unknown default`.
    public enum TLSPinningMode: Sendable {
        /// Rejects new assignments unless the TLS connection passes system trust evaluation and matches a pin.
        case required
    }

    /// The certificates of the validated chain that a pin can match.
    ///
    /// More targets may be added in a minor version. A `switch` over this type needs `@unknown default`.
    public enum PinTarget: Sendable {
        /// Pins match only the server (leaf) certificate.
        ///
        /// Use this target only when you control the server key. A renewal with a new key breaks the connection
        /// unless the new key is already pinned.
        case leaf

        /// Pins match an issuer certificate: any certificate after the leaf in the validated chain, including the
        /// trust anchor. The leaf certificate never matches.
        ///
        /// Use this target when the provider renews the leaf certificate and its key automatically.
        case issuer
    }

    /// An exact HTTPS origin, a pin target, and the public key pins that the SDK trusts for the origin.
    ///
    /// A pin is the base64-encoded SHA-256 hash of the DER-encoded `SubjectPublicKeyInfo` of a certificate.
    /// You can compute a pin with this command:
    ///
    /// ```
    /// openssl x509 -in certificate.pem -pubkey -noout \
    ///   | openssl pkey -pubin -outform DER \
    ///   | openssl dgst -sha256 -binary | base64
    /// ```
    ///
    /// A policy needs at least two different pins: an active key and a backup key. The backup key lets the
    /// server change keys or issuers without a new application release. The SDK validates the policy when the
    /// Flags feature is enabled.
    public struct TLSPinPolicy: Sendable {
        /// The exact HTTPS origin, for example `https://flags.example.com`.
        ///
        /// The origin must use the `https` scheme and must not contain a path, query, fragment, or credentials.
        /// Only this host and port are trusted. Subdomains and redirects to other origins are rejected.
        public let origin: URL

        /// The certificates of the validated chain that ``spkiSHA256Pins`` can match.
        public let pinTarget: PinTarget

        /// The base64-encoded SHA-256 hashes of the trusted `SubjectPublicKeyInfo` structures.
        public let spkiSHA256Pins: Set<String>

        /// Creates a custom pin policy.
        ///
        /// - Parameters:
        ///   - origin: The exact HTTPS origin that serves flag assignments.
        ///   - pinTarget: The certificates of the validated chain that the pins can match.
        ///   - spkiSHA256Pins: At least two base64-encoded SHA-256 hashes of `SubjectPublicKeyInfo` structures.
        public init(origin: URL, pinTarget: PinTarget, spkiSHA256Pins: Set<String>) {
            self.origin = origin
            self.pinTarget = pinTarget
            self.spkiSHA256Pins = spkiSHA256Pins
        }

        /// The Datadog staging profile, version 1.
        ///
        /// It pins the issuers of the Fastly-managed staging certificate, which is renewed automatically with new
        /// leaf keys.
        public static var datadogStagingV1: TLSPinPolicy {
            stagingV1
        }

        // The pins are the real public keys of the Certainly CAs. The endpoint is pending provisioning and live
        // validation (ddoghq/terraform-config PR 62220). Starfield Root G2, which cross-signs Certainly Intermediate R1,
        // is not pinned: it issues for too many other services.
        private static let stagingV1 = TLSPinPolicy(
            // swiftlint:disable:next force_unwrapping
            origin: URL(string: "https://protected.ff-cdn.datad0g.com")!,
            pinTarget: .issuer,
            spkiSHA256Pins: [
                // Certainly Intermediate R1 (RSA 2048), valid to 2032-06-21. It issues the current certificates.
                "oW7smChMJRcnzTObF7K+HzInReAPTxB/L1h6eZTmw9Q=",
                // Certainly Intermediate E1 (EC P-384), valid to 2031-04-01 for the copy signed by Certainly Root E1.
                "XkxTESlVMF59ZsGRFSBQJyCYjYJYNYkLwv/sqaDnMJA=",
                // Certainly Root R1 (RSA 4096), valid to 2046-04-01.
                "P5Pz/PedIl0hPu9qSj9Yhc+E/j16ejwRVTUXaIwOIQA=",
                // Certainly Root E1 (EC P-384), valid to 2046-04-01.
                "HvZGJdqi5dQz10Sa4xogDRAl4AEqj+z6cJMvi1mbdd0=",
            ]
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
    let pinTarget: Flags.ResponseProtection.PinTarget
    /// Canonical base64 encodings of 32-byte SHA-256 hashes.
    let pins: Set<String>
    /// The URL of the flag assignments request.
    let assignmentsURL: URL

    var cacheIdentifier: String {
        let target: String
        switch pinTarget {
        case .leaf: target = "leaf"
        case .issuer: target = "issuer"
        }
        let canonical = "tls-pinning;required;https://\(host):\(port);\(target);" + pins.sorted().joined(separator: ",")
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
            pinTarget: profile.pinTarget,
            pins: pins,
            assignmentsURL: profile.origin
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
        ResolvedTLSPinPolicy(host: host, port: port, pinTarget: pinTarget, pins: pins, assignmentsURL: assignmentsURL)
    }
}
