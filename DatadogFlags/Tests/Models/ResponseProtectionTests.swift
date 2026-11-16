/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class ResponseProtectionTests: XCTestCase {
    private let pinA = TLSPinningFixtures.pinP256
    private let pinB = TLSPinningFixtures.pinP384
    private let origin = URL(string: "https://flags.example.com")!

    // MARK: - Policy validation

    func testValidPolicyResolvesToTheOriginAndCanonicalPins() throws {
        // Given
        let profile = Flags.ResponseProtection.TLSPinPolicy(origin: URL(string: "https://FLAGS.example.com/")!, pinTarget: .leaf, spkiSHA256Pins: [pinA, pinB])

        // When
        let policy = try ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: nil).get()

        // Then
        XCTAssertEqual(policy.host, "flags.example.com")
        XCTAssertEqual(policy.port, 443)
        XCTAssertEqual(policy.pins, [pinA, pinB])
        XCTAssertEqual(policy.assignmentsURL.absoluteString, "https://FLAGS.example.com/precompute-assignments")
        XCTAssertTrue(policy.permits(host: "flags.example.com", port: 443))
        XCTAssertFalse(policy.permits(host: "sub.flags.example.com", port: 443))
        XCTAssertEqual(policy.pinTarget, .leaf)
    }

    func testInvalidPoliciesAreRejected() {
        let cases: [(origin: String, pins: Set<String>, error: ResponseProtectionConfigurationError)] = [
            ("http://flags.example.com", [pinA, pinB], .originIsNotHTTPS),
            ("flags.example.com", [pinA, pinB], .originIsNotHTTPS),
            ("https://flags.example.com/path", [pinA, pinB], .originIsNotExact),
            ("https://flags.example.com?query=1", [pinA, pinB], .originIsNotExact),
            ("https://flags.example.com#fragment", [pinA, pinB], .originIsNotExact),
            ("https://user:password@flags.example.com", [pinA, pinB], .originIsNotExact),
            ("https://flags.example.com", [pinA], .notEnoughPins(minimum: 2)),
            ("https://flags.example.com", [], .notEnoughPins(minimum: 2)),
            ("https://flags.example.com", [pinA, "not base64"], .invalidPin),
            ("https://flags.example.com", [pinA, Data(count: 20).base64EncodedString()], .invalidPin),
            ("https://flags.example.com", [pinA, " \(pinB)"], .invalidPin),
        ]

        for (origin, pins, expectedError) in cases {
            let profile = Flags.ResponseProtection.TLSPinPolicy(origin: URL(string: origin)!, pinTarget: .leaf, spkiSHA256Pins: pins)

            let result = ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: nil)

            XCTAssertEqual(result.failure, expectedError, "\(origin) \(pins)")
        }
    }

    func testCustomFlagsEndpointMustUseThePolicyOrigin() throws {
        let profile = Flags.ResponseProtection.TLSPinPolicy(origin: origin, pinTarget: .leaf, spkiSHA256Pins: [pinA, pinB])

        // Same origin: the custom endpoint is the assignments URL.
        let sameOrigin = URL(string: "https://flags.example.com:443/custom/precompute")!
        XCTAssertEqual(try ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: sameOrigin).get().assignmentsURL, sameOrigin)

        // Another origin: no trust is inherited.
        for endpoint in ["https://proxy.example.com/assignments", "http://flags.example.com/assignments", "https://flags.example.com:8443"] {
            XCTAssertEqual(
                ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: URL(string: endpoint)!).failure,
                .customEndpointOutsidePolicy,
                endpoint
            )
        }
    }

    func testCacheIdentifierDependsOnTheOriginTargetAndPinsOnly() throws {
        func identifier(
            _ origin: String,
            _ pins: Set<String>,
            _ pinTarget: Flags.ResponseProtection.PinTarget = .leaf
        ) throws -> String {
            let result = ResolvedTLSPinPolicy.make(
                from: .init(origin: URL(string: origin)!, pinTarget: pinTarget, spkiSHA256Pins: pins),
                customFlagsEndpoint: nil
            )
            return try result.get().cacheIdentifier
        }

        let reference = try identifier("https://flags.example.com", [pinA, pinB])
        XCTAssertEqual(try identifier("https://FLAGS.example.com:443/", [pinB, pinA]), reference)
        XCTAssertNotEqual(try identifier("https://flags.example.com", [pinA, TLSPinningFixtures.pinUnused]), reference)
        XCTAssertNotEqual(try identifier("https://other.example.com", [pinA, pinB]), reference)
        XCTAssertNotEqual(try identifier("https://flags.example.com", [pinA, pinB], .issuer), reference)
        XCTAssertTrue(reference.hasPrefix("tls-pinning-v1:"))
    }

    func testStagingProfilePinsTheCertainlyIssuers() throws {
        // Given
        let profile = Flags.ResponseProtection.TLSPinPolicy.datadogStagingV1
        let policy = try ResolvedTLSPinPolicy.make(from: profile, customFlagsEndpoint: nil).get()

        // When
        // The pins are computed from the public CA certificates, not copied from the profile.
        let issuerPins = try [
            TLSPinningFixtures.certainlyIntermediateR1,
            TLSPinningFixtures.certainlyRootR1,
            TLSPinningFixtures.certainlyRootE1,
        ].map { certificate in
            try XCTUnwrap(SecCertificateCopyKey(certificate).flatMap(SubjectPublicKeyInfo.sha256Base64(of:)))
        }

        // Then
        XCTAssertEqual(profile.origin.absoluteString, "https://protected.ff-cdn.datad0g.com")
        XCTAssertEqual(profile.pinTarget, .issuer)
        XCTAssertEqual(issuerPins, [
            "oW7smChMJRcnzTObF7K+HzInReAPTxB/L1h6eZTmw9Q=",
            "P5Pz/PedIl0hPu9qSj9Yhc+E/j16ejwRVTUXaIwOIQA=",
            "HvZGJdqi5dQz10Sa4xogDRAl4AEqj+z6cJMvi1mbdd0=",
        ])
        XCTAssertEqual(profile.spkiSHA256Pins, Set(issuerPins))
        XCTAssertEqual(policy.pins, Set(issuerPins))
        XCTAssertEqual(policy.assignmentsURL.absoluteString, "https://protected.ff-cdn.datad0g.com/precompute-assignments")
        // Starfield Root G2 is too broad to pin.
        XCTAssertFalse(profile.spkiSHA256Pins.contains("gI1os/q0iEpflxrOfRBVDXqVoWN3Tz7Dav/7IT++THQ="))
    }

    // MARK: - Resolution and reporting

    func testNoProtectionResolvesToNil() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        XCTAssertNil(ResponseProtectionPolicy.resolve(nil, customFlagsEndpoint: nil, telemetry: NOPTelemetry()))
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty)
    }

    func testInvalidRequiredPolicyIsReportedAndFailsClosed() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let telemetry = TelemetryMock()
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }
        let protection = Flags.ResponseProtection.tlsPinning(
            mode: .required,
            profile: .init(origin: origin, pinTarget: .leaf, spkiSHA256Pins: [pinA])
        )

        // When
        let policy = ResponseProtectionPolicy.resolve(protection, customFlagsEndpoint: nil, telemetry: telemetry)

        // Then
        XCTAssertEqual(policy, .misconfigured)
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(printFunction.printedMessages.count, 1)
        XCTAssertTrue(try XCTUnwrap(printFunction.printedMessage).contains("at least 2 different pins"))
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    func testStagingProfileResolvesWithoutWarnings() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        let policy = ResponseProtectionPolicy.resolve(
            .tlsPinning(mode: .required, profile: .datadogStagingV1),
            customFlagsEndpoint: nil,
            telemetry: NOPTelemetry()
        )

        // Then
        guard case .tlsPinning? = policy else {
            return XCTFail("Expected a TLS pinning policy, got \(String(describing: policy))")
        }
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty)
        XCTAssertTrue(printFunction.printedMessages.isEmpty)
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
