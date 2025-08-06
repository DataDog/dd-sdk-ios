/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RequestBuilderTests: XCTestCase {
    private let mockEvents: [Event] = [
        .init(data: "event 1".utf8Data),
        .init(data: "event 2".utf8Data),
        .init(data: "event 3".utf8Data)
    ]

    func testItCreatesPOSTRequest() {
        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )

        // When
        let request = builder.request(for: mockEvents, with: .mockAny(), execution: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsRUMIntakeURL() {
        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )

        // When
        func url(for site: DatadogSite) -> String {
            let request = builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/rum")
        XCTAssertEqual(url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/rum")
        XCTAssertEqual(url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/rum")
        XCTAssertEqual(url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/rum")
        XCTAssertEqual(url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/rum")
        XCTAssertEqual(url(for: .ap2), "https://browser-intake-ap2-datadoghq.com/api/v2/rum")
        XCTAssertEqual(url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/rum")
    }

    func testItSetsCustomIntakeURL() {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = RequestBuilder(
            customIntakeURL: randomURL,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )

        // When
        func url(for site: DatadogSite) -> String {
            let request = builder.request(for: mockEvents, with: .mockWith(site: site), execution: .mockAny())
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

    func testItSetsRUMQueryParameters() {
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomService: String = .mockRandom(among: .alphanumerics)
        let randomEnv: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomAttempt: UInt = .mockRandom()
        let randomStatus: Int = .mockRandom()

        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )
        let context: DatadogContext = .mockWith(
            service: randomService,
            env: randomEnv,
            version: randomVersion,
            source: randomSource,
            sdkVersion: randomSDKVersion
        )
        let execution: ExecutionContext = .mockWith(previousResponseCode: randomStatus, attempt: randomAttempt)

        // When
        let request = builder.request(for: mockEvents, with: context, execution: execution)

        // Then
        let expextedQuery = "ddsource=\(randomSource)&ddtags=service:\(randomService),version:\(randomVersion),sdk_version:\(randomSDKVersion),env:\(randomEnv),retry_count:\(randomAttempt + 1),last_failure_status:\(randomStatus)"
        XCTAssertEqual(request.url?.query, expextedQuery)
    }

    func testItSetsVariantAsExtraQueryParameter() {
        let randomVariant: String = .mockRandom(among: .alphanumerics)

        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )
        let context: DatadogContext = .mockWith(variant: randomVariant)

        // When
        let request = builder.request(for: mockEvents, with: context, execution: .mockAny())

        // Then
        let query = request.url?.query ?? ""
        XCTAssertTrue(query.contains(",variant:\(randomVariant)"))
    }

    func testItSetsRUMHTTPHeaders() {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomService: String = .mockRandom(among: .alphanumerics)
        let randomEnv: String = .mockRandom(among: .alphanumerics)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomOrigin: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()

        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            service: randomService,
            env: randomEnv,
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
        let request = builder.request(for: mockEvents, with: context, execution: .mockAny())

        // Then
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Encoding"], "deflate")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomOrigin)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() {
        // Given
        let builder = RequestBuilder(
            customIntakeURL: nil,
            eventsFilter: .init(),
            telemetry: NOPTelemetry()
        )

        // When
        let request = builder.request(for: mockEvents, with: .mockAny(), execution: .mockAny())

        // Then
        let decompressed = zlib.decode(request.httpBody!)!
        let actual = String(data: decompressed, encoding: .utf8)
        let expected = """
        event 1
        event 2
        event 3
        """
        XCTAssertEqual(expected, actual, "It must separate each event with newline character")
    }
}
