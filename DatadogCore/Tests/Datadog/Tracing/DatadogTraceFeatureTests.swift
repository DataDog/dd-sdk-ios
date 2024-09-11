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

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

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
                    device: .mockWith(
                        name: randomDeviceName,
                        osName: randomDeviceOSName,
                        osVersion: randomDeviceOSVersion
                    )
                )
            ),
            applicationVersion: randomApplicationVersion,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: randomBackgroundTasksEnabled
        )
        defer { core.flushAndTearDown() }

        // Given
        Trace.enable(with: .init(customEndpoint: randomUploadURL), in: core)

        // When
        let tracer = Tracer.shared(in: core)
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

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
        defer { core.flushAndTearDown() }

        // Given
        Trace.enable(in: core)

        // When
        let tracer = Tracer.shared(in: core)

        tracer.startSpan(operationName: "operation 1").finish()
        tracer.startSpan(operationName: "operation 2").finish()
        tracer.startSpan(operationName: "operation 3").finish()

        let payload = try XCTUnwrap(server.waitAndReturnRequests(count: 1)[0].httpBody)

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
}
