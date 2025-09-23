/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class ExposureRequestBuilderTests: XCTestCase {
    private let mockEvents: [Event] = [
        .init(data: "event 1".utf8Data),
        .init(data: "event 2".utf8Data),
        .init(data: "event 3".utf8Data)
    ]

    func testItCreatesPOSTRequest() throws {
        // Given
        let builder = ExposureRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )

        // When
        let request = try builder.request(for: mockEvents, with: .mockAny(), execution: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsExposuresIntakeURL() {
        // Given
        let builder = ExposureRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )

        // When
        func url(for site: DatadogSite) -> String {
            let request = try! builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/exposures")
        XCTAssertEqual(url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/exposures")
        XCTAssertEqual(url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/exposures")
        XCTAssertEqual(url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/exposures")
        XCTAssertEqual(url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/exposures")
        XCTAssertEqual(url(for: .ap2), "https://browser-intake-ap2-datadoghq.com/api/v2/exposures")
        XCTAssertEqual(url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/exposures")
    }

    func testItSetsCustomIntakeURL() throws {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = ExposureRequestBuilder(
            customIntakeURL: randomURL,
            telemetry: NOPTelemetry()
        )

        // When
        func url(for site: DatadogSite) -> String {
            let request = try! builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        let expectedURL = randomURL.absoluteStringWithoutQuery
        XCTAssertEqual(url(for: .us1), expectedURL)
        XCTAssertEqual(url(for: .us3), expectedURL)
        XCTAssertEqual(url(for: .us5), expectedURL)
        XCTAssertEqual(url(for: .eu1), expectedURL)
        XCTAssertEqual(url(for: .ap1), expectedURL)
        XCTAssertEqual(url(for: .ap2), expectedURL)
        XCTAssertEqual(url(for: .us1_fed), expectedURL)
    }

    func testItSetsExposureQueryParameters() throws {
        let randomSource: String = .mockRandom(among: .alphanumerics)

        // Given
        let builder = ExposureRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )
        let context: DatadogContext = .mockWith(source: randomSource)

        // When
        let request = try builder.request(for: mockEvents, with: context, execution: .mockAny())

        // Then
        let expectedQuery = "ddsource=\(randomSource)"
        XCTAssertEqual(request.url?.query, expectedQuery)
    }

    func testItSetsExposureHTTPHeaders() throws {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomOrigin: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()

        // Given
        let builder = ExposureRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            version: randomVersion,
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

        // When
        let request = try builder.request(for: mockEvents, with: context, execution: .mockAny())

        // Then
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomOrigin)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() throws {
        // Given
        let builder = ExposureRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )

        // When
        let request = try builder.request(for: mockEvents, with: .mockAny(), execution: .mockAny())

        // Then
        let httpBodyData = try XCTUnwrap(request.httpBody)
        let actual = String(data: httpBodyData, encoding: .utf8)
        let expected = """
        event 1
        event 2
        event 3
        """
        XCTAssertEqual(expected, actual, "It must separate each event with newline character")
    }
}
