/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - HTTP Message

    func testItUsesExpectedHTTPMessage() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: "FoobarApp",
                    applicationVersion: "2.1.0",
                    serviceName: "service-name",
                    environment: "environment-name",
                    source: "abc"
                )
            ),
            dependencies: .mockWith(
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )
        defer { RUMFeature.instance?.deinitialize() }

        let monitor = RUMMonitor.initialize()

        // Starting first view sends `application_start` action event
        monitor.startView(viewController: mockView)

        let request = server.waitAndReturnRequests(count: 1)[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.query,
            """
            ddsource=abc&ddtags=service:service-name,version:2.1.0,sdk_version:\(sdkVersion),env:environment-name
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWith(
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
                        defaultUploadDelay: 1,
                        minUploadDelay: 1,
                        maxUploadDelay: 1,
                        uploadDelayChangeRate: 0
                    )
                )
            )
        )
        defer { RUMFeature.instance?.deinitialize() }

        let fileWriter = try XCTUnwrap(RUMFeature.instance?.storage.writer)
        fileWriter.write(value: RUMDataModelMock(attribute: "1st event"))
        fileWriter.write(value: RUMDataModelMock(attribute: "2nd event"))
        fileWriter.write(value: RUMDataModelMock(attribute: "3rd event"))

        let payload = server.waitAndReturnRequests(count: 1)[0].httpBody!

        // Expected payload format:
        // ```
        // event1JSON
        // event2JSON
        // event3JSON
        // ```

        let eventMatchers = try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertEqual((try eventMatchers[0].model() as RUMDataModelMock).attribute, "1st event")
        XCTAssertEqual((try eventMatchers[1].model() as RUMDataModelMock).attribute, "2nd event")
        XCTAssertEqual((try eventMatchers[2].model() as RUMDataModelMock).attribute, "3rd event")
    }
}
