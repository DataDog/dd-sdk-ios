/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(TracingFeature.instance)
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(TracingFeature.instance)
        temporaryFeatureDirectories.delete()
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
        let randomDeviceModel: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()
        let randomEncryption: DataEncryption? = Bool.random() ? DataEncryptionMock() : nil

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))

        // Given
        TracingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: randomApplicationName,
                    applicationVersion: randomApplicationVersion,
                    source: randomSource,
                    origin: randomOrigin,
                    sdkVersion: randomSDKVersion,
                    encryption: randomEncryption
                ),
                uploadURL: randomUploadURL,
                clientToken: randomClientToken
            ),
            dependencies: .mockWith(
                mobileDevice: .mockWith(model: randomDeviceModel, osName: randomDeviceOSName, osVersion: randomDeviceOSVersion)
            )
        )
        defer { TracingFeature.instance?.deinitialize() }

        // When
        let tracer = Tracer.initialize(configuration: .init()).dd
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(requestURL.absoluteString, randomUploadURL.absoluteString)
        XCTAssertNil(requestURL.query)
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomApplicationVersion) CFNetwork (\(randomDeviceModel); \(randomDeviceOSName)/\(randomDeviceOSVersion))
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
        TracingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(
                    storagePerformance: StoragePerformanceMock(
                        maxFileSize: .max,
                        maxDirectorySize: .max,
                        maxFileAgeForWrite: .distantFuture, // write all spans to single file,
                        minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                        maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                        maxObjectsInFile: 3, // write 3 spans to payload,
                        maxObjectSize: .max
                    ),
                    uploadPerformance: UploadPerformanceMock(
                        initialUploadDelay: 0.5, // wait enough until spans are written,
                        minUploadDelay: 1,
                        maxUploadDelay: 1,
                        uploadDelayChangeRate: 0
                    )
                )
            )
        )
        defer { TracingFeature.instance?.deinitialize() }

        let tracer = Tracer.initialize(configuration: .init()).dd

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
