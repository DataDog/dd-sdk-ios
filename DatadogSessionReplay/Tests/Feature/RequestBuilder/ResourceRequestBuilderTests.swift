/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal
@testable import DatadogSessionReplay
@testable import TestUtilities

class ResourceRequestBuilderTests: XCTestCase {
    private let resources = [
        EnrichedResource.mockRandom(),
        EnrichedResource.mockRandom(),
        EnrichedResource.mockRandom()
    ]
    private var mockEvents: [Event] {
        return resources.map { .mockWith(data: try! JSONEncoder().encode($0)) }
    }

    func testItCreatesPOSTRequest() throws {
        // Given
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: mockEvents, with: .mockRandom(), execution: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsIntakeURL() {
        // Given
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(try url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/replay")
        XCTAssertEqual(try url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .ap2), "https://browser-intake-ap2-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/replay")
    }

    func testItSetsCustomIntakeURL() {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = ResourceRequestBuilder(customUploadURL: randomURL, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
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
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: mockEvents, with: .mockRandom(), execution: .init(previousResponseCode: nil, attempt: 0))

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
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            version: randomVersion,
            source: randomSource,
            sdkVersion: randomSDKVersion,
            applicationName: randomApplicationName,
            device: .mockWith(
                name: randomDeviceName,
                osName: randomDeviceOSName,
                osVersion: randomDeviceOSVersion
            )
        )

        // When
        let request = try builder.request(for: mockEvents, with: context, execution: .mockAny())

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
        XCTAssertNotNil(request.allHTTPHeaderFields?["Content-Encoding"], "It must us no compression, because multipart file is compressed separately")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() throws {
        // Given
        let multipartSpy = MultipartBuilderSpy()
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock(), multipartBuilder: multipartSpy)

        // When
        let request = try builder.request(for: mockEvents, with: .mockRandom(), execution: .mockAny())

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: "multipart/form-data; boundary=\(multipartSpy.boundary)"))

        for i in 0..<resources.count {
            XCTAssertNotNil(multipartSpy.formFiles[i].filename)
            XCTAssertGreaterThan(multipartSpy.formFiles[i].data.count, 0)
            XCTAssertEqual(multipartSpy.formFiles[i].mimeType, resources[i].mimeType)
        }

        XCTAssertEqual(multipartSpy.formFiles.last?.filename, "blob")
        XCTAssertGreaterThan(multipartSpy.formFiles.last?.data.count ?? 0, 0)
        XCTAssertEqual(multipartSpy.formFiles.last?.mimeType, "application/json")
    }

    func testWhenBatchDataIsMalformed_itThrows() {
        // Given
        let builder = ResourceRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When, Then
        XCTAssertThrowsError(try builder.request(for: [.mockWith(data: "abc".utf8Data)], with: .mockRandom(), execution: .mockAny()))
    }
}
#endif
