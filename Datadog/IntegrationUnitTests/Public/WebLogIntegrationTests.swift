/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if !os(tvOS)

import DatadogInternal

@testable import DatadogLogs
@testable import DatadogRUM
@testable import DatadogWebViewTracking

class WebLogIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var controller: WKUserContentControllerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.1.1",
                serverTimeOffset: 123
            )
        )

        controller = WKUserContentControllerMock()

        WebViewTracking.enable(
            tracking: controller,
            hosts: [],
            hostsSanitizer: HostsSanitizer(),
            logsSampleRate: 100,
            in: core
        )
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        controller = nil
    }

    func testWebLogIntegration() throws {
        // Given
        Logs.enable(in: core)

        let body = """
        {
            "eventType": "log",
            "event": {
                "date" : \(1_635_932_927_012),
                "status": "debug",
                "message": "message",
                "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
                "view": {
                    "referrer": "",
                    "url": "https://datadoghq.dev/browser-sdk-test-playground"
                }
            }
        }
        """

        // When
        controller.send(body: body)
        controller.flush()

        // Then
        let logMatcher = try XCTUnwrap(core.waitAndReturnLogMatchers().first)
        try logMatcher.assertItFullyMatches(
            jsonString: """
        {
            "date": \(1_635_932_927_012 + 123.toInt64Milliseconds),
            "ddtags": "version:1.1.1,env:test",
            "message": "message",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "debug",
            "view": {
                "referrer": "",
                "url": "https://datadoghq.dev/browser-sdk-test-playground"
            },
        }
        """
        )
    }

    func testWebLogWithRUMIntegration() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: UUID = .mockRandom()

        Logs.enable(in: core)
        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        let body = """
        {
            "eventType": "log",
            "event": {
                "date" : \(1_635_932_927_012),
                "status": "debug",
                "message": "message",
                "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
                "view": {
                    "referrer": "",
                    "url": "https://datadoghq.dev/browser-sdk-test-playground"
                }
            }
        }
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: body)
        controller.flush()

        // Then
        let expectedUUID = randomUUID.uuidString.lowercased()
        let logMatcher = try XCTUnwrap(core.waitAndReturnLogMatchers().first)
        try logMatcher.assertItFullyMatches(
            jsonString: """
        {
            "date": \(1_635_932_927_012 + 123.toInt64Milliseconds),
            "ddtags": "version:1.1.1,env:test",
            "message": "message",
            "application_id": "\(randomApplicationID)",
            "session_id": "\(expectedUUID)",
            "view.id": "\(expectedUUID)",
            "status": "debug",
            "view": {
                "referrer": "",
                "url": "https://datadoghq.dev/browser-sdk-test-playground"
            },
        }
        """
        )
    }
}

#endif
