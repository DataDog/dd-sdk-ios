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

/// Fetches real assignments from the Datadog staging endpoint through the pinned `URLSession`.
///
/// These tests use the network and are skipped unless `DD_FLAGS_STAGING_CLIENT_TOKEN` is set.
/// Pass the token to the simulator test process with the `TEST_RUNNER_` prefix, for example
/// `TEST_RUNNER_DD_FLAGS_STAGING_CLIENT_TOKEN=<token> xcodebuild test ... -only-testing:DatadogFlagsTests/ResponseProtectionLiveTests`.
/// Never write the token into the repository.
final class ResponseProtectionLiveTests: XCTestCase {
    private static let tokenVariable = "DD_FLAGS_STAGING_CLIENT_TOKEN"
    private let origin = URL(string: "https://protected.ff-cdn.datad0g.com")!
    private let flagKey = "dogmail-assignment-flag-treatment-control"
    private let defaultValue = "default"
    /// The SPKI pin of the leaf that the staging endpoint served on 2026-11-16. It changes when Fastly renews the key.
    private let liveLeafPin = "hgvFJ1yECRJcFdzcv5AwkIyeo1LphKXbqKSUP4TYpCk="

    private var clientToken = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        let token = ProcessInfo.processInfo.environment[Self.tokenVariable]
        try XCTSkipUnless(token?.isEmpty == false, "Set \(Self.tokenVariable) to run the live staging tests.")
        clientToken = token ?? ""
    }

    func testStagingProfileFetchesAssignments() throws {
        let outcome = try fetch(responseProtection: .tlsPinning(mode: .required, profile: .datadogStagingV1))

        XCTAssertEqual(outcome.assignmentsHost, "protected.ff-cdn.datad0g.com")
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.value, "treatment")
        XCTAssertTrue(outcome.rejections.isEmpty, "\(outcome.rejections)")
    }

    func testIssuerPolicyWithUnrelatedPinsIsRejected() throws {
        let profile = Flags.ResponseProtection.TLSPinPolicy(
            origin: origin,
            pinTarget: .issuer,
            spkiSHA256Pins: [TLSPinningFixtures.pinUnused, TLSPinningFixtures.pinRoot]
        )

        let outcome = try fetch(responseProtection: .tlsPinning(mode: .required, profile: profile))

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.value, defaultValue)
        XCTAssertTrue(outcome.rejections.contains { $0.contains("matches a pin") }, "\(outcome.rejections)")
    }

    func testLeafPolicyWithTheLiveLeafKeyFetchesAssignments() throws {
        let profile = Flags.ResponseProtection.TLSPinPolicy(
            origin: origin,
            pinTarget: .leaf,
            spkiSHA256Pins: [liveLeafPin, TLSPinningFixtures.pinUnused]
        )

        let outcome = try fetch(responseProtection: .tlsPinning(mode: .required, profile: profile))

        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.value, "treatment")
        XCTAssertTrue(outcome.rejections.isEmpty, "\(outcome.rejections)")
    }

    func testUnprotectedControlFetchesAssignmentsFromTheStagingSiteEndpoint() throws {
        // Without response protection and without `customFlagsEndpoint`, the `.staging` site selects the endpoint.
        XCTAssertEqual(DatadogSite.staging.flagsEndpoint().absoluteString, "https://preview.ff-cdn.datad0g.com")

        let outcome = try fetch(responseProtection: nil)

        XCTAssertNil(outcome.assignmentsHost)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.value, "treatment")
    }

    /// Records the chain that the system builds for the staging endpoint. The challenge is cancelled, so no request is sent.
    func testRecordTheValidatedChain() throws {
        let recorder = ChainRecorder()
        let session = URLSession(configuration: .ephemeral, delegate: recorder, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let completed = expectation(description: "completed")
        session.dataTask(with: origin.appendingPathComponent("precompute-assignments")) { _, _, _ in completed.fulfill() }.resume()
        waitForExpectations(timeout: 30)

        let chain = try XCTUnwrap(recorder.chain)
        for (index, certificate) in chain.enumerated() {
            let pin = SecCertificateCopyKey(certificate).flatMap(SubjectPublicKeyInfo.sha256Base64(of:)) ?? "unsupported key"
            print("[live chain] \(index): \(SecCertificateCopySubjectSummary(certificate) as String? ?? "?") pin=\(pin)")
        }
        XCTAssertTrue(recorder.isTrusted)
        XCTAssertGreaterThanOrEqual(chain.count, 2)
    }

    // MARK: - Helpers

    private struct Outcome {
        let assignmentsHost: String?
        let error: FlagsError?
        let value: String
        let rejections: [String]
    }

    private func fetch(responseProtection: Flags.ResponseProtection?) throws -> Outcome {
        let logger = CoreLoggerMock()
        let dd = DD.mockWith(logger: logger)
        defer { dd.reset() }
        let core = DatadogCoreProxy(
            context: .mockWith(site: .staging, clientToken: clientToken, env: "staging", source: "ios", trackingConsent: .granted)
        )
        defer { try? core.flushAndTearDown() }

        var configuration = Flags.Configuration(
            trackExposures: false,
            trackEvaluations: false,
            rumIntegrationEnabled: false
        )
        configuration.responseProtection = responseProtection
        Flags.enable(with: configuration, in: core)
        let feature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        var assignmentsHost: String?
        if case .tlsPinning(let policy)? = feature.responseProtection {
            assignmentsHost = policy.assignmentsURL.host
        }

        let client = FlagsClient.create(name: "live-\(UUID().uuidString)", in: core)
        let completed = expectation(description: "context set")
        var result: Result<Void, FlagsError>?
        client.setEvaluationContext(.init(targetingKey: "e2e-user-1", attributes: [:])) {
            result = $0
            completed.fulfill()
        }
        waitForExpectations(timeout: 30)

        var error: FlagsError?
        if case .failure(let failure)? = result {
            error = failure
        }
        let value = client.getStringValue(key: flagKey, defaultValue: defaultValue)
        let rejections = logger.errorMessages.filter { $0.contains("Rejected a flag assignments") }
        for log in logger.recordedLogs {
            print("[live log] \(log.level): \(log.message) \(log.error.map { "\($0)" } ?? "")")
        }
        print("[live result] host=\(assignmentsHost ?? "site default: \(DatadogSite.staging.flagsEndpoint())") error=\(error.map { "\($0)" } ?? "none") value=\(value)")
        return Outcome(assignmentsHost: assignmentsHost, error: error, value: value, rejections: rejections)
    }
}

private final class ChainRecorder: NSObject, URLSessionTaskDelegate {
    private(set) var chain: [SecCertificate]?
    private(set) var isTrusted = false

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = challenge.protectionSpace.serverTrust {
            isTrusted = SecTrustEvaluateWithError(trust, nil)
            chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
