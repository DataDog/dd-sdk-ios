/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

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

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            userInfoProvider: .mockAny(),
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
                    device: .mockWith(
                        name: randomDeviceName,
                        osName: randomDeviceOSName,
                        osVersion: randomDeviceOSVersion
                    )
                )
            ),
            applicationVersion: randomApplicationVersion
        )
        defer { core.flushAndTearDown() }

        // Given
        let featureConfiguration: RUMFeature.Configuration = .mockWith(uploadURL: randomUploadURL)
        let feature: RUMFeature = try core.create(
            configuration: createRUMConfiguration(configuration: featureConfiguration),
            featureSpecificConfiguration: featureConfiguration
        )
        core.register(feature: feature)

        // When
        let monitor = RUMMonitor.initialize(in: core)
        monitor.startView(viewController: mockView) // on starting the first view we sends `application_start` action event

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(requestURL.absoluteString.starts(with: randomUploadURL.absoluteString + "?"))
        XCTAssertEqual(
            requestURL.query,
            """
            ddsource=\(randomSource)&ddtags=service:\(randomServiceName),version:\(randomApplicationVersion),sdk_version:\(randomSDKVersion),env:\(randomEnvironmentName)
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

    // MARK: - HTTP Message with included variant

    func testItUsesExpectedVariantQueryParaemterInMessage() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let randomVariant: String = .mockAny()

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            userInfoProvider: .mockAny(),
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
            contextProvider: .mockWith(
                context: .mockWith(variant: randomVariant)
            ),
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        // Given
        let featureConfiguration: RUMFeature.Configuration = .mockAny()
        let feature: RUMFeature = try core.create(
            configuration: createRUMConfiguration(configuration: featureConfiguration),
            featureSpecificConfiguration: featureConfiguration
        )
        core.register(feature: feature)

        // When
        let monitor = RUMMonitor.initialize(in: core)
        monitor.startView(viewController: mockView) // on starting the first view we sends `application_start` action event

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
        let requestURL = try XCTUnwrap(request.url)
        let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        let tagsItem = components?.queryItems?.first(where: { $0.name == "ddtags" })
        XCTAssertTrue(tagsItem?.value?.contains("variant:\(randomVariant)") == true)
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            userInfoProvider: .mockAny(),
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
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        // Given
        let featureConfiguration: RUMFeature.Configuration = .mockAny()
        let feature: RUMFeature = try core.create(
            configuration: createRUMConfiguration(configuration: featureConfiguration),
            featureSpecificConfiguration: featureConfiguration
        )
        core.register(feature: feature)

        let writer = feature.storage.writer(for: .granted, forceNewBatch: false)
        writer.write(value: RUMDataModelMock(attribute: "1st event"), metadata: RUMViewEvent.Metadata(id: "1", documentVersion: 1))
        writer.write(value: RUMDataModelMock(attribute: "2nd event"), metadata: RUMViewEvent.Metadata(id: "2", documentVersion: 1))
        writer.write(value: RUMDataModelMock(attribute: "3rd event"), metadata: RUMViewEvent.Metadata(id: "1", documentVersion: 2))

        let payload = try XCTUnwrap(server.waitAndReturnRequests(count: 1)[0].httpBody)

        // Expected payload format:
        // event1JSON is skipped in favor of event3JSON which is same event with higher document revision
        // ```
        // event2JSON
        // event3JSON
        // ```

        let eventMatchers = try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertEqual((try eventMatchers[0].model() as RUMDataModelMock).attribute, "2nd event")
        XCTAssertEqual((try eventMatchers[1].model() as RUMDataModelMock).attribute, "3rd event")
    }
}
