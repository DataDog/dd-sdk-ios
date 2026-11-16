/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Security
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class TLSPinningSessionDelegateTests: XCTestCase {
    private let host = TLSPinningFixtures.host

    // MARK: - Trust evaluation

    func testMatchingPinIsTrusted() throws {
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused])

        XCTAssertEqual(evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443), .trusted)
    }

    func testActiveAndBackupPinsAcceptBothKeys() throws {
        // Given an A+B client
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinP384])

        // Then it accepts key A and, after the server switches, key B
        XCTAssertEqual(evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443), .trusted)
        XCTAssertEqual(evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP384), host: host, port: 443), .trusted)
    }

    func testActiveOnlyClientRejectsTheBackupKey() throws {
        // Given an A-only client
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused])

        // Then it rejects key B
        XCTAssertEqual(
            evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP384), host: host, port: 443),
            .rejected(.pinMismatch)
        )
    }

    func testWrongPinsAreRejected() throws {
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinUnused, TLSPinningFixtures.pinRSA4096])

        XCTAssertEqual(
            evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443),
            .rejected(.pinMismatch)
        )
    }

    func testRSALeafPinsAreTrusted() throws {
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinRSA2048, TLSPinningFixtures.pinRSA4096])

        XCTAssertEqual(evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafRSA2048), host: host, port: 443), .trusted)
        XCTAssertEqual(evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafRSA4096), host: host, port: 443), .trusted)
    }

    func testIssuerPinDoesNotSatisfyALeafPolicy() throws {
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinRoot, TLSPinningFixtures.pinUnused])

        XCTAssertEqual(
            evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443),
            .rejected(.pinMismatch)
        )
    }

    func testHostOutsideThePolicyIsRejected() throws {
        let evaluator = try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused])
        let leaf = TLSPinningFixtures.leafP256OtherHost

        XCTAssertEqual(evaluator.evaluate(try trust(leaf: leaf), host: "other.example.com", port: 443), .rejected(.hostOutsidePolicy))
        XCTAssertEqual(evaluator.evaluate(try trust(leaf: leaf), host: "sub.\(host)", port: 443), .rejected(.hostOutsidePolicy))
        XCTAssertEqual(evaluator.evaluate(try trust(leaf: leaf), host: host, port: 8_443), .rejected(.hostOutsidePolicy))
    }

    func testMatchingPinDoesNotReplaceSystemTrustEvaluation() throws {
        let pins: Set<String> = [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused]

        // Hostname: the certificate is for another host, although its key matches the pin.
        let evaluator = try makeEvaluator(pins: pins)
        XCTAssertEqual(
            evaluator.evaluate(try trust(leaf: TLSPinningFixtures.leafP256OtherHost), host: host, port: 443),
            .rejected(.systemTrustFailed)
        )

        // Chain: the root is not trusted by the system.
        let untrusted = try makeEvaluator(pins: pins, anchors: nil)
        XCTAssertEqual(
            untrusted.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443),
            .rejected(.systemTrustFailed)
        )

        // Time: the certificate has expired.
        let expired = try makeEvaluator(pins: pins, verificationDate: Date(timeIntervalSince1970: 1_830_297_600)) // 2028-01-01
        XCTAssertEqual(
            expired.evaluate(try trust(leaf: TLSPinningFixtures.leafP256), host: host, port: 443),
            .rejected(.systemTrustFailed)
        )
    }

    // MARK: - Issuer pins

    func testIntermediatePinAcceptsRenewedLeafWithANewKey() throws {
        // Given an issuer policy that pins the intermediate
        let evaluator = try makeIssuerEvaluator(pins: [TLSPinningFixtures.pinIssuerIntermediate, TLSPinningFixtures.pinUnused])

        // Then both leaf keys issued by it are trusted
        XCTAssertEqual(evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafA), host: host, port: 443), .trusted)
        XCTAssertEqual(evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafB), host: host, port: 443), .trusted)
    }

    func testRootPinIsTrusted() throws {
        let evaluator = try makeIssuerEvaluator(pins: [TLSPinningFixtures.pinIssuerRoot, TLSPinningFixtures.pinUnused])

        XCTAssertEqual(evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafA), host: host, port: 443), .trusted)
    }

    func testIssuerPolicyRejectsAChainFromAnotherTrustedRoot() throws {
        // Given a device that also trusts an interception root
        let evaluator = try makeIssuerEvaluator(pins: [TLSPinningFixtures.pinIssuerIntermediate, TLSPinningFixtures.pinIssuerRoot])
        let intercepted = try trust(leaf: TLSPinningFixtures.interceptionLeaf, intermediates: [TLSPinningFixtures.interceptionRoot])

        // Then system trust succeeds, but no issuer matches a pin
        XCTAssertEqual(evaluator.evaluate(intercepted, host: host, port: 443), .rejected(.pinMismatch))
    }

    func testLeafPinDoesNotSatisfyAnIssuerPolicy() throws {
        let evaluator = try makeIssuerEvaluator(pins: [TLSPinningFixtures.pinIssuedLeafA, TLSPinningFixtures.pinUnused])

        XCTAssertEqual(
            evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafA), host: host, port: 443),
            .rejected(.pinMismatch)
        )
    }

    func testIssuerPinDoesNotSatisfyALeafPolicyInAnIntermediateChain() throws {
        let evaluator = try makeEvaluator(
            pins: [TLSPinningFixtures.pinIssuerIntermediate, TLSPinningFixtures.pinIssuerRoot],
            anchors: [TLSPinningFixtures.issuerRoot]
        )

        XCTAssertEqual(
            evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafA), host: host, port: 443),
            .rejected(.pinMismatch)
        )
    }

    func testIssuerPinDoesNotReplaceSystemTrustEvaluation() throws {
        // The issuer root is not an anchor here, so the chain is not trusted although the intermediate is pinned.
        let evaluator = try makeEvaluator(
            pins: [TLSPinningFixtures.pinIssuerIntermediate, TLSPinningFixtures.pinIssuerRoot],
            pinTarget: .issuer,
            anchors: [TLSPinningFixtures.interceptionRoot]
        )

        XCTAssertEqual(
            evaluator.evaluate(try issuedTrust(leaf: TLSPinningFixtures.issuedLeafA), host: host, port: 443),
            .rejected(.systemTrustFailed)
        )
    }

    // MARK: - Delegate

    func testDelegateUsesTheCredentialForATrustedServer() throws {
        // Given
        let delegate = TLSPinningSessionDelegate(evaluator: try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinP384]))
        let challenge = try serverTrustChallenge(leaf: TLSPinningFixtures.leafP384)

        // When
        var disposition: URLSession.AuthChallengeDisposition?
        var credential: URLCredential?
        delegate.urlSession(.shared, didReceive: challenge) { disposition = $0; credential = $1 }

        // Then
        XCTAssertEqual(disposition, .useCredential)
        XCTAssertNotNil(credential)
    }

    func testDelegateCancelsTheChallengeOnPinMismatch() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let delegate = TLSPinningSessionDelegate(evaluator: try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused]))
        let challenge = try serverTrustChallenge(leaf: TLSPinningFixtures.leafP384)
        let task = URLSession.shared.dataTask(with: URL(string: "https://\(host)")!)

        // When
        var sessionDisposition: URLSession.AuthChallengeDisposition?
        var taskDisposition: URLSession.AuthChallengeDisposition?
        var credential: URLCredential?
        delegate.urlSession(.shared, didReceive: challenge) { sessionDisposition = $0; credential = $1 }
        delegate.urlSession(.shared, task: task, didReceive: challenge) { taskDisposition = $0; _ = $1 }

        // Then
        // Cancelling the challenge fails the task before the request is sent.
        XCTAssertEqual(sessionDisposition, .cancelAuthenticationChallenge)
        XCTAssertEqual(taskDisposition, .cancelAuthenticationChallenge)
        XCTAssertNil(credential)
        XCTAssertEqual(dd.logger.errorMessages.count, 2)
        XCTAssertTrue(try XCTUnwrap(dd.logger.errorMessages.first).contains("matches a pin"))
    }

    func testDelegateKeepsDefaultHandlingForOtherChallenges() throws {
        // Given
        let delegate = TLSPinningSessionDelegate(evaluator: try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused]))
        let protectionSpace = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: NSURLProtectionSpaceHTTPS,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        // When
        var disposition: URLSession.AuthChallengeDisposition?
        delegate.urlSession(.shared, didReceive: challenge(protectionSpace)) { disposition = $0; _ = $1 }

        // Then
        XCTAssertEqual(disposition, .performDefaultHandling)
    }

    func testDelegateFollowsOnlyRedirectsWithinThePinnedOrigin() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let delegate = TLSPinningSessionDelegate(evaluator: try makeEvaluator(pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinUnused]))
        let task = URLSession.shared.dataTask(with: URL(string: "https://\(host)")!)
        let redirect = HTTPURLResponse(url: URL(string: "https://\(host)")!, statusCode: 307, httpVersion: nil, headerFields: nil)!

        for (target, isFollowed) in [
            ("https://\(host)/other-path", true),
            ("https://other.example.com/precompute-assignments", false),
            ("http://\(host)/precompute-assignments", false),
            ("https://\(host):8443/precompute-assignments", false),
        ] {
            // When
            var followed: URLRequest?
            delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: URL(string: target)!)) { followed = $0 }

            // Then
            XCTAssertEqual(followed != nil, isFollowed, target)
        }
    }

    // MARK: - Helpers

    private func makeEvaluator(
        pins: Set<String>,
        pinTarget: Flags.ResponseProtection.PinTarget = .leaf,
        anchors: [SecCertificate]? = [TLSPinningFixtures.root],
        verificationDate: Date = TLSPinningFixtures.verificationDate
    ) throws -> TLSPinningTrustEvaluator {
        let result = ResolvedTLSPinPolicy.make(
            from: .init(origin: URL(string: "https://\(host)")!, pinTarget: pinTarget, spkiSHA256Pins: pins),
            customFlagsEndpoint: nil
        )
        return TLSPinningTrustEvaluator(policy: try result.get(), anchorCertificates: anchors, verificationDate: verificationDate)
    }

    private func trust(leaf: SecCertificate, intermediates: [SecCertificate] = [TLSPinningFixtures.root]) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            [leaf] + intermediates as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        XCTAssertEqual(status, errSecSuccess)
        return try XCTUnwrap(trust)
    }

    private func makeIssuerEvaluator(pins: Set<String>) throws -> TLSPinningTrustEvaluator {
        try makeEvaluator(
            pins: pins,
            pinTarget: .issuer,
            anchors: [TLSPinningFixtures.issuerRoot, TLSPinningFixtures.interceptionRoot]
        )
    }

    private func issuedTrust(leaf: SecCertificate) throws -> SecTrust {
        try trust(leaf: leaf, intermediates: [TLSPinningFixtures.issuerIntermediate, TLSPinningFixtures.issuerRoot])
    }

    private func serverTrustChallenge(leaf: SecCertificate) throws -> URLAuthenticationChallenge {
        challenge(ServerTrustProtectionSpace(host: host, port: 443, trust: try trust(leaf: leaf)))
    }

    private func challenge(_ protectionSpace: URLProtectionSpace) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: ChallengeSenderMock()
        )
    }
}

private final class ServerTrustProtectionSpace: URLProtectionSpace {
    private let trust: SecTrust

    init(host: String, port: Int, trust: SecTrust) {
        self.trust = trust
        super.init(
            host: host,
            port: port,
            protocol: NSURLProtectionSpaceHTTPS,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var serverTrust: SecTrust? {
        trust
    }
}

private final class ChallengeSenderMock: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
