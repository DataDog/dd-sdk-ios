/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCore
@testable import DatadogRUM

class RUMFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryCoreDirectory.create()
    }

    override func tearDown() {
        temporaryCoreDirectory.delete()
        super.tearDown()
    }

    // MARK: - HTTP Message

    func testItUsesExpectedHTTPMessage() throws {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomApplicationVersion: String = .mockRandom(among: .decimalDigits)
        let randomServiceName: String = .mockRandom(among: .alphanumerics)
        let randomEnvironmentName: String = .mockRandom(among: .alphanumerics)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomOrigin: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomUploadURL: URL = .mockRandom()
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()
        let randomEncryption: DataEncryption? = Bool.random() ? DataEncryptionMock() : nil
        let randomBackgroundTasksEnabled: Bool = .mockRandom()

        let httpClient = HTTPClientMock(responseCode: 200)

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(
                storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                uploadPerformance: .veryQuick
            ),
            httpClient: httpClient,
            encryption: randomEncryption,
            contextProvider: .mockWith(
                context: .mockWith(
                    clientToken: randomClientToken,
                    service: randomServiceName,
                    env: randomEnvironmentName,
                    version: randomApplicationVersion,
                    source: randomSource,
                    sdkVersion: randomSDKVersion,
                    ciAppOrigin: randomOrigin,
                    applicationName: randomApplicationName,
                    device: .mockWith(name: randomDeviceName),
                    os: .mockWith(
                        name: randomDeviceOSName,
                        version: randomDeviceOSVersion
                    )
                )
            ),
            applicationVersion: randomApplicationVersion,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: randomBackgroundTasksEnabled
        )

        // Given
        RUM.enable(with: .mockWith { $0.customEndpoint = randomUploadURL }, in: core)

        // When
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: .mockAny()) // on starting the first view we sends `application_start` action event
        core.flushAndTearDown()

        // Then
        let requests = httpClient.requestsSent()
        let request = try XCTUnwrap(requests.first)
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(requestURL.absoluteString.starts(with: randomUploadURL.absoluteString + "?"))
        XCTAssertEqual(
            requestURL.query,
            """
            ddsource=\(randomSource)
            """
        )
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomApplicationVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Encoding"], "deflate")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomOrigin)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let httpClient = HTTPClientMock(responseCode: 200)

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(
                storagePerformance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write all events to single file,
                    minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                    maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                    maxObjectsInFile: .max,
                    maxObjectSize: .max
                ),
                uploadPerformance: UploadPerformanceMock(
                    initialUploadDelay: 0.5, // wait enough until events are written,
                    minUploadDelay: 1,
                    maxUploadDelay: 1,
                    uploadDelayChangeRate: 0
                )
            ),
            httpClient: httpClient,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

        // Given
        RUM.enable(with: .mockAny(), in: core)
        core.flushAndTearDown()

        let requests = httpClient.requestsSent()
        XCTAssertEqual(requests.count, 1)
        let payload = try XCTUnwrap(requests.first?.decompressed().httpBody)

        // Expected payload format:
        // ```
        // view event JSON     - "application launch" view
        // action event JSON   - "application start" action
        // ```

        let eventMatchers = try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertFalse(eventMatchers.filterRUMEvents(ofType: RUMViewEvent.self).isEmpty, "It must include view event")
    }

    func testItOnlyKeepsOneViewEventPerPayload() throws {
        let httpClient = HTTPClientMock(responseCode: 200)

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(
                storagePerformance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write all events to single file,
                    minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                    maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                    maxObjectsInFile: .max,
                    maxObjectSize: .max
                ),
                uploadPerformance: UploadPerformanceMock(
                    initialUploadDelay: 0.5, // wait enough until events are written,
                    minUploadDelay: 1,
                    maxUploadDelay: 1,
                    uploadDelayChangeRate: 0
                )
            ),
            httpClient: httpClient,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

        // Given
        RUM.enable(with: .mockAny(), in: core)

        // When
        RUMMonitor.shared(in: core).addError(message: "1st error")
        RUMMonitor.shared(in: core).addError(message: "2nd error")
        RUMMonitor.shared(in: core).addError(message: "3rd error")
        core.flushAndTearDown()

        // Then
        let requests = httpClient.requestsSent()
        XCTAssertEqual(requests.count, 1)
        let payload = try XCTUnwrap(requests.first?.decompressed().httpBody)
        let eventMatchers = try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        let viewMatchers = eventMatchers.filterRUMEvents(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewMatchers.count, 1, "It should keep only one view event")
        try viewMatchers[0].model(ofType: RUMViewEvent.self) { event in
            XCTAssertEqual(event.view.error.count, 3, "It should track 3 errors")
        }
    }
}

/// Tests for the synchronous sampling store that `RUMFeature` exposes to features which cannot wait
/// for the RUM context to travel the message bus.
class RUMSessionSamplingStoreTests: XCTestCase {
    /// A session UUID whose Knuth hash fraction is roughly 6.4%.
    ///
    /// That band is what makes the two sampling policies distinguishable: the session is kept at a
    /// 20% rate applied on its own, and dropped at the 2% that results from composing 20% with a 10%
    /// session rate. A vector outside the band would be decided the same way by both policies, so the
    /// assertions below would pass even if the policies were swapped.
    private let sessionUUID = UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171")!
    private let sessionID = "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171"
    private let sessionRate: SampleRate = 10
    private let featureRate: SampleRate = 20

    private func makeStore() -> RUMSessionSamplingStore {
        let store = RUMSessionSamplingStore()
        store.setSession(
            id: sessionID,
            sampler: DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        )
        return store
    }

    func testThePolicyVectorSeparatesTheTwoPolicies() {
        // A guard on the test's own premise: if the hash math ever changes, every assertion below
        // becomes vacuous rather than failing, so assert the separation explicitly.
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        XCTAssertTrue(sessionSampler.isSampled, "Precondition: the session itself must be sampled at \(sessionRate)%")
        XCTAssertTrue(
            DeterministicSampler(seed: sessionSampler.seed, samplingRate: featureRate).isSampled,
            "Precondition: the vector must be kept at the feature rate applied alone"
        )
        XCTAssertFalse(
            sessionSampler.combined(with: featureRate).isSampled,
            "Precondition: the vector must be dropped at the composed rate"
        )
    }

    func testFeatureRatePolicy_appliesTheFeatureRateAlone() throws {
        // When
        let snapshot = try XCTUnwrap(makeStore().sessionSamplingSnapshot(for: .featureRate, rate: featureRate))

        // Then — the session supplies only the seed, so a 20% feature rate stays 20%.
        XCTAssertTrue(snapshot.isSampled)
        XCTAssertEqual(
            snapshot.isSampled,
            DeterministicSampler(uuid: sessionUUID, samplingRate: featureRate).isSampled,
            "The decision must match a sampler built from the session seed at the feature rate"
        )
    }

    func testCombinedPolicy_multipliesTheFeatureRateWithTheSessionRate() throws {
        // When
        let snapshot = try XCTUnwrap(makeStore().sessionSamplingSnapshot(for: .combinedWithSessionRate, rate: featureRate))

        // Then — 20% of a 10% session is an effective 2%, which drops this vector.
        XCTAssertFalse(snapshot.isSampled)
        XCTAssertEqual(
            snapshot.isSampled,
            DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate).combined(with: featureRate).isSampled,
            "The decision must match the composed rate"
        )
    }

    func testCombinedPolicyAtMaxRate_returnsTheSessionsOwnDecision() throws {
        // When
        let snapshot = try XCTUnwrap(
            makeStore().sessionSamplingSnapshot(for: .combinedWithSessionRate, rate: .maxSampleRate)
        )

        // Then — composing with 100% leaves the session rate untouched, which is how a consumer asks
        // for "is this session tracked at all".
        XCTAssertEqual(snapshot.isSampled, DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate).isSampled)
        XCTAssertTrue(snapshot.isSampled)
    }

    func testSnapshotCarriesTheIDOfTheSessionThatMadeTheDecision() throws {
        // Given
        let store = makeStore()
        let otherUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        let otherID = "c5b3c4ab-fa4a-4de9-8199-a522131ec48a"

        // When — the session rolls over between two reads
        let first = try XCTUnwrap(store.sessionSamplingSnapshot(for: .featureRate, rate: featureRate))
        store.setSession(id: otherID, sampler: DeterministicSampler(uuid: otherUUID, samplingRate: sessionRate))
        let second = try XCTUnwrap(store.sessionSamplingSnapshot(for: .featureRate, rate: featureRate))

        // Then — each snapshot pairs an ID with the decision made for that same session
        XCTAssertEqual(first.sessionID, sessionID)
        XCTAssertEqual(first.isSampled, DeterministicSampler(uuid: sessionUUID, samplingRate: featureRate).isSampled)
        XCTAssertEqual(second.sessionID, otherID)
        XCTAssertEqual(second.isSampled, DeterministicSampler(uuid: otherUUID, samplingRate: featureRate).isSampled)
    }

    func testWithNoSession_itReturnsNilSoConsumersFallBack() {
        XCTAssertNil(RUMSessionSamplingStore().sessionSamplingSnapshot(for: .featureRate, rate: featureRate))
        XCTAssertNil(RUMSessionSamplingStore().sessionSamplingSnapshot(for: .combinedWithSessionRate, rate: featureRate))
    }

    func testAfterClearingTheSession_itReturnsNil() {
        // Given
        let store = makeStore()
        XCTAssertNotNil(store.sessionSamplingSnapshot(for: .featureRate, rate: featureRate))

        // When — this is what `stopSession()` produces
        store.clearSession()

        // Then
        XCTAssertNil(store.sessionSamplingSnapshot(for: .featureRate, rate: featureRate))
    }

    func testConcurrentReadsAndWrites() {
        let store = makeStore()
        let otherUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Readers run on the request path while RUM rolls the session over, so both must be safe.
        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration % 4 == 0 {
                store.setSession(
                    id: "session-\(iteration)",
                    sampler: DeterministicSampler(uuid: otherUUID, samplingRate: self.sessionRate)
                )
            } else if iteration % 7 == 0 {
                store.clearSession()
            } else {
                _ = store.sessionSamplingSnapshot(for: .combinedWithSessionRate, rate: self.featureRate)
            }
        }
    }
}
