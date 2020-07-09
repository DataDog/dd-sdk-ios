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
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - HTTP Headers

    func testItUsesExpectedHTTPHeaders() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationName: "FoobarApp",
                applicationVersion: "2.1.0"
            ),
            mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
        )
        defer { RUMFeature.instance = nil }

        // TODO: RUMM-585 Replace with real data created by `RUMMonitor`
        struct DummyRUMMEvent: Encodable {
            let someAttribute = "foo"
        }
        let fileWriter = try XCTUnwrap(RUMFeature.instance?.storage.writer)
        fileWriter.write(value: DummyRUMMEvent())

        let httpHeaders = server.waitAndReturnRequests(count: 1)[0].allHTTPHeaderFields
        XCTAssertEqual(httpHeaders?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(httpHeaders?["Content-Type"], "text/plain;charset=UTF-8")
    }

    // MARK: - Payload Format

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
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
                    uploadDelayDecreaseFactor: 1
                )
            )
        )
        defer { RUMFeature.instance = nil }

        // TODO: RUMM-585 Replace with real data created by `RUMMonitor`
        struct DummyRUMMEvent: Codable {
            let someAttribute = "foo"
        }
        let fileWriter = try XCTUnwrap(RUMFeature.instance?.storage.writer)
        fileWriter.write(value: DummyRUMMEvent()) // 1st event
        fileWriter.write(value: DummyRUMMEvent()) // 2nd event
        fileWriter.write(value: DummyRUMMEvent()) // 3rd event

        let payload = server.waitAndReturnRequests(count: 1)[0].httpBody!

        // Expected payload format:
        // ```
        // event1JSON
        // event2JSON
        // event3JSON
        // ```

        // Expect payload to be 3 newline-separated JSONs
        // TODO: RUMM-585 Use RUMEventMatcher: let rumEventMatchers = try RUMeventMacher.fromNewlineSeparatedJSONObjectsData(payload)
        // Split payload by `\n`
        let jsonObjectsData = payload.split(separator: 10) // 10 stands for `\n` in ASCII
        XCTAssertEqual(jsonObjectsData.count, 3)
        let jsonDecoder = JSONDecoder()
        // Ensure each line of data is a valid JSON string
        XCTAssertNoThrow(try jsonDecoder.decode(DummyRUMMEvent.self, from: jsonObjectsData[0]))
        XCTAssertNoThrow(try jsonDecoder.decode(DummyRUMMEvent.self, from: jsonObjectsData[1]))
        XCTAssertNoThrow(try jsonDecoder.decode(DummyRUMMEvent.self, from: jsonObjectsData[2]))
    }
}
