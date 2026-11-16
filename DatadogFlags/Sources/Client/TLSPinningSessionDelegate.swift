/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Security
import DatadogInternal

/// Decides if a server trust satisfies a TLS pin policy.
internal struct TLSPinningTrustEvaluator {
    enum Decision: Equatable {
        case trusted
        case rejected(Rejection)
    }

    enum Rejection: String {
        case hostOutsidePolicy = "host outside the pin policy"
        case systemTrustFailed = "system trust evaluation failed"
        case missingLeafCertificate = "no leaf certificate"
        case pinMismatch = "no public key in the pinned part of the chain matches a pin"
    }

    let policy: ResolvedTLSPinPolicy
    /// Replaces the system anchors. Tests only.
    var anchorCertificates: [SecCertificate]?
    /// Replaces the current time for validity checks. Tests only.
    var verificationDate: Date?

    init(policy: ResolvedTLSPinPolicy, anchorCertificates: [SecCertificate]? = nil, verificationDate: Date? = nil) {
        self.policy = policy
        self.anchorCertificates = anchorCertificates
        self.verificationDate = verificationDate
    }

    func evaluate(_ trust: SecTrust, host: String, port: Int) -> Decision {
        guard policy.permits(host: host, port: port) else {
            return .rejected(.hostOutsidePolicy)
        }

        // Run the default evaluation first: chain, hostname, and validity time. A pin never replaces it.
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        if let anchorCertificates {
            SecTrustSetAnchorCertificates(trust, anchorCertificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }
        if let verificationDate {
            SecTrustSetVerifyDate(trust, verificationDate as CFDate)
        }
        guard SecTrustEvaluateWithError(trust, nil) else {
            return .rejected(.systemTrustFailed)
        }

        // The chain that the system validated, from the leaf to the trust anchor.
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], !chain.isEmpty else {
            return .rejected(.missingLeafCertificate)
        }
        let candidates: ArraySlice<SecCertificate>
        switch policy.pinTarget {
        case .leaf:
            candidates = chain.prefix(1)
        case .issuer:
            // Every certificate after the leaf, including the anchor. The leaf never satisfies an issuer pin.
            candidates = chain.dropFirst()
        }
        let matches = candidates.contains { certificate in
            // A key type without a `SubjectPublicKeyInfo` encoding cannot match a pin.
            guard let key = SecCertificateCopyKey(certificate), let pin = SubjectPublicKeyInfo.sha256Base64(of: key) else {
                return false
            }
            return policy.pins.contains(pin)
        }
        return matches ? .trusted : .rejected(.pinMismatch)
    }
}

/// The delegate of the `URLSession` that fetches flag assignments under required TLS pinning.
///
/// It is installed only on the assignment session, so other SDK uploads keep their transport.
/// A rejected server trust cancels the challenge, so the request headers and body are never sent.
internal final class TLSPinningSessionDelegate: NSObject, URLSessionTaskDelegate {
    let evaluator: TLSPinningTrustEvaluator

    init(evaluator: TLSPinningTrustEvaluator) {
        self.evaluator = evaluator
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Follow only redirects within the pinned origin. Otherwise the redirect response completes the task.
        guard let url = request.url, evaluator.policy.permits(url: url) else {
            DD.logger.error("Rejected a flag assignments redirect outside the TLS pin policy.")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            // Other challenges, such as HTTP authentication, do not decide the server identity.
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = protectionSpace.serverTrust else {
            DD.logger.error("Rejected a flag assignments connection: no server trust.")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        switch evaluator.evaluate(trust, host: protectionSpace.host, port: protectionSpace.port) {
        case .trusted:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .rejected(let rejection):
            DD.logger.error("Rejected a flag assignments connection to '\(protectionSpace.host)': \(rejection.rawValue).")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
