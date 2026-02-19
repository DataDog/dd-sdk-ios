/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling

class RequestBuilderTests: XCTestCase {
    private let rumContext: RUMCoreContext = .mockRandom()

    let profileEvent = ProfileEvent(
        family: .mockRandom(),
        runtime: .mockRandom(),
        version: .mockRandom(),
        start: .mockRandomInThePast(),
        end: Date(),
        attachments: [],
        tags: .mockAny(),
        additionalAttributes: mockRandomAttributes()
    )

    let profileData: Data = .mockRandom()

    private func mockEvent() throws -> Event {
        let encoder = JSONEncoder.dd.default()
        return try Event(
            data: encoder.encode(profileData),
            metadata: encoder.encode(profileEvent)
        )
    }

    func testItCreatesPOSTRequest() throws {
        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: [mockEvent()], with: .mockAny(), execution: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsIntakeURL() {
        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: [mockEvent()], with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(try url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/profile")
        XCTAssertEqual(try url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/profile")
        XCTAssertEqual(try url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/profile")
        XCTAssertEqual(try url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/profile")
        XCTAssertEqual(try url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/profile")
        XCTAssertEqual(try url(for: .ap2), "https://browser-intake-ap2-datadoghq.com/api/v2/profile")
        XCTAssertEqual(try url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/profile")
    }

    func testItSetsCustomIntakeURL() {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = RequestBuilder(customUploadURL: randomURL, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: [mockEvent()], with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        let expectedURL = randomURL.absoluteStringWithoutQuery
        XCTAssertEqual(try url(for: .us1), expectedURL)
        XCTAssertEqual(try url(for: .us3), expectedURL)
        XCTAssertEqual(try url(for: .us5), expectedURL)
        XCTAssertEqual(try url(for: .eu1), expectedURL)
        XCTAssertEqual(try url(for: .ap1), expectedURL)
        XCTAssertEqual(try url(for: .ap2), expectedURL)
        XCTAssertEqual(try url(for: .us1_fed), expectedURL)
    }

    func testItSetsQueryParameters() throws {
        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockRandom()

        // When
        let request = try builder.request(for: [mockEvent()], with: context, execution: .mockWith(previousResponseCode: nil, attempt: 0))

        // Then
        XCTAssertEqual(request.url!.query, "ddtags=retry_count:1")
    }

    func testItSetsHTTPHeaders() throws {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()

        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            version: randomVersion,
            source: randomSource,
            sdkVersion: randomSDKVersion,
            applicationName: randomApplicationName,
            device: .mockWith(name: randomDeviceName),
            os: .mockWith(
                name: randomDeviceOSName,
                version: randomDeviceOSVersion
            )
        )

        // When
        let request = try builder.request(for: [mockEvent()], with: context, execution: .mockAny())

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: #"multipart\/form-data; boundary=([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})"#))
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomSource)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() throws {
        // Given
        let event = try mockEvent()
        let multipartSpy = MultipartBuilderSpy()
        let builder = RequestBuilder(multipartBuilder: multipartSpy, customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: [event], with: .mockAny(), execution: .mockAny())

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: "multipart/form-data; boundary=\(multipartSpy.boundary)"))
        XCTAssertEqual(multipartSpy.formFiles.count, 2)

        let eventFile = multipartSpy.formFiles[0]
        XCTAssertEqual(eventFile.filename, "event.json")
        XCTAssertEqual(eventFile.mimeType, "application/json")
        XCTAssertEqual(eventFile.data, event.metadata)

        let pprofFile = multipartSpy.formFiles[1]
        XCTAssertEqual(pprofFile.filename, "wall.pprof")
        XCTAssertEqual(pprofFile.mimeType, "application/octet-stream")
        XCTAssertEqual(pprofFile.data, profileData)
    }

    func testWhenBatchDataHasMoreThanOneProfile() {
        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When, Then
        XCTAssertThrowsError(try builder.request(for: .mockAny(count: 2), with: .mockAny(), execution: .mockAny()))
    }

    func testWhenBatchDataIsMissingMetadata() {
        // Given
        let builder = RequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When, Then
        XCTAssertThrowsError(try builder.request(
            for: [.mockWith(data: .mockRandom(), metadata: nil)],
            with: .mockAny(),
            execution: .mockAny()
        ))
    }
}
#endif // !os(watchOS)
