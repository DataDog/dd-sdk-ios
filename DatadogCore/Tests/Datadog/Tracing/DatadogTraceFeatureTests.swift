/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace
@testable import DatadogCore

class DatadogTraceFeatureTests: XCTestCase {
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
        let randomApplicationVersion: String = .mockRandom()
        let randomSource: String = .mockRandom()
        let randomOrigin: String = .mockRandom()
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
        Trace.enable(with: .init(customEndpoint: randomUploadURL), in: core)

        // When
        let tracer = Tracer.shared(in: core)
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()
        core.flushAndTearDown()

        // Then
        let requests = httpClient.requestsSent()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(requestURL.host, randomUploadURL.host)
        XCTAssertEqual(requestURL.path, randomUploadURL.path)
        XCTAssertNil(requestURL.query)
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
                    maxObjectsInFile: 3, // write 3 spans to payload,
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
        Trace.enable(in: core)

        // When
        let tracer = Tracer.shared(in: core)

        tracer.startSpan(operationName: "operation 1").finish()
        tracer.startSpan(operationName: "operation 2").finish()
        tracer.startSpan(operationName: "operation 3").finish()
        core.flushAndTearDown()

        let requests = httpClient.requestsSent()
        XCTAssertEqual(requests.count, 1)
        let payload = try XCTUnwrap(requests.first?.decompressed().httpBody)

        // Expected payload format:
        // ```
        // span1JSON
        // span2JSON
        // span3JSON
        // ```

        let spanMatchers = try SpanMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertEqual(try spanMatchers[0].operationName(), "operation 1")
        XCTAssertEqual(try spanMatchers[1].operationName(), "operation 2")
        XCTAssertEqual(try spanMatchers[2].operationName(), "operation 3")
    }

    // MARK: - Client-Side Stats

    func testWhenClientStatsBucketExceedsTheStorageEventLimit_itIsStillUploaded() throws {
        let httpClient = HTTPClientMock(responseCode: 202)
        let core = makeClientStatsCore(httpClient: httpClient, maxObjectsInFile: 1) // one request per stored event
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // Given: one bucket that encodes to more than the 1 MB storage event limit.
        addWideLatencySpans(to: stats.concentrator, endingAt: Date().timeIntervalSince1970.dd.toNanoseconds)

        // When
        core.flushAndTearDown()

        // Then: the bucket is stored and uploaded as several pieces instead of being rejected.
        XCTAssertGreaterThan(statsRequests(in: httpClient).count, 1)
    }

    func testWhenStoredClientStatsExceedTheBatchLimit_eachRequestStaysWithinIt() throws {
        let httpClient = HTTPClientMock(responseCode: 202)
        let core = makeClientStatsCore(httpClient: httpClient, maxObjectsInFile: .max) // only the size limits files
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // Given: two windows whose pieces add up to more than one batch.
        let end = Date().timeIntervalSince1970.dd.toNanoseconds
        addWideLatencySpans(to: stats.concentrator, endingAt: end)
        addWideLatencySpans(to: stats.concentrator, endingAt: end + 20_000_000_000) // a later window; earlier ones merge into the oldest

        // When
        core.flushAndTearDown()

        // Then
        let requests = statsRequests(in: httpClient)
        XCTAssertGreaterThan(requests.count, 1)
        for request in requests {
            let body = try XCTUnwrap(request.decompressed().httpBody)
            XCTAssertLessThanOrEqual(body.count, Int(ClientStatsFeature.maxBatchSize))
        }
    }

    func testWhenAllDataIsCleared_clientStatsBufferedBeforeAreNeverUploaded() throws {
        let httpClient = HTTPClientMock(responseCode: 202)
        let core = makeClientStatsCore(httpClient: httpClient, maxObjectsInFile: .max)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.record(.mockWith(startTime: 0, duration: 100))

        // When
        core.clearAllData()
        core.flushAndTearDown()

        // Then
        XCTAssertTrue(statsRequests(in: httpClient).isEmpty)
    }

    func testWhenConsentIsRevokedAndGrantedAgain_clientStatsCollectedBeforeAreNeverUploaded() throws {
        // Repeated, because consent changes reach the feature through the message bus, which can run behind
        // the flushes and writes this exercises.
        for iteration in 0..<20 {
            temporaryCoreDirectory.delete()
            temporaryCoreDirectory.create()
            let httpClient = HTTPClientMock(responseCode: 202)
            let core = makeClientStatsCore(httpClient: httpClient, maxObjectsInFile: .max, initialConsent: .pending)
            let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
            core.flush() // deliver the initial context

            // Given: stats collected while consent is pending, and a flush racing the consent changes.
            stats.record(.mockWith(resource: "before-revocation", startTime: 0, duration: 100))
            if iteration.isMultiple(of: 2) {
                stats.flushStats(.teardown)
            }

            // When: consent is revoked, then granted again, with a flush right behind.
            core.set(trackingConsent: .notGranted)
            core.set(trackingConsent: .granted)
            stats.flushStats(.teardown)
            core.flush()
            stats.record(.mockWith(resource: "after-grant", startTime: 0, duration: 100))
            core.flushAndTearDown()

            // Then
            // MessagePack keeps strings as raw UTF-8, so resource names can be found in the bodies.
            let bodies = try statsRequests(in: httpClient).map { String(decoding: try XCTUnwrap($0.decompressed().httpBody), as: UTF8.self) }
            XCTAssertFalse(bodies.contains { $0.contains("before-revocation") }, "Iteration \(iteration)")
            XCTAssertTrue(bodies.contains { $0.contains("after-grant") }, "Iteration \(iteration)")
        }
    }

    // MARK: - Client-Side Stats Helpers

    /// A core with the real 1 MB storage event limit and no file size limit of its own, so the
    /// client stats feature's limits apply.
    private func makeClientStatsCore(httpClient: HTTPClientMock, maxObjectsInFile: Int, initialConsent: TrackingConsent = .granted) -> DatadogCore {
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: initialConsent,
            performance: .combining(
                storagePerformance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture,
                    minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                    maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                    maxObjectsInFile: maxObjectsInFile,
                    maxObjectSize: PerformancePreset.mockAny().maxObjectSize // the real 1 MB event limit
                ),
                uploadPerformance: .veryQuick
            ),
            httpClient: httpClient,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 100,
            backgroundTasksEnabled: .mockAny()
        )
        var config = Trace.Configuration()
        config.featureFlags[.clientSideStats] = true
        Trace.enable(with: config, in: core)
        return core
    }

    /// 100 groups of fast and very slow successful and failed requests ending together, whose bucket
    /// encodes to more than the 1 MB storage event limit. Snapshots go straight to the concentrator,
    /// so they are all aggregated before the teardown flush.
    private func addWideLatencySpans(to concentrator: StatsConcentrator, endingAt end: UInt64) {
        for group in 0..<100 {
            for duration: UInt64 in [1_000_000, 60_000_000_000] {
                for isError in [false, true] {
                    concentrator.add(.mockWith(resource: "GET /\(group)", isError: isError, startTime: end - duration, duration: duration))
                }
            }
        }
    }

    private func statsRequests(in httpClient: HTTPClientMock) -> [URLRequest] {
        httpClient.requestsSent().filter { $0.url?.path.hasSuffix("api/v0.2/stats") == true }
    }
}
