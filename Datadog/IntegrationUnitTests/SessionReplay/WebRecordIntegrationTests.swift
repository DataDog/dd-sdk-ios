/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if !os(tvOS)
import WebKit

import TestUtilities
@testable import DatadogRUM
@testable import DatadogWebViewTracking
@_spi(Internal) @testable import DatadogSessionReplay

class WebRecordIntegrationTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: DatadogCoreProxy!
    private var webView: WKWebView!
    private var controller: WKUserContentControllerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.1.1",
                serverTimeOffset: 123
            )
        )

        controller = WKUserContentControllerMock()
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool() // do not share cookies between instances: prevent leak
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        WebViewTracking.enable(webView: webView, in: core)
    }

    override func tearDown() {
        WebViewTracking.disable(webView: webView)
        core.flushAndTearDown()
        core = nil
        webView = nil
        controller = nil
    }

    func testWebRecordIntegration() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: UUID = .mockRandom()
        let randomBrowserViewID: UUID = .mockRandom()

        SessionReplay.enable(with: SessionReplay.Configuration(replaySampleRate: 100), in: core)
        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        let body = """
        {
            "eventType": "record",
            "event": {
                "timestamp" : \(1635932927012),
                "type": 2
            },
            "view": { "id": "\(randomBrowserViewID.uuidString.lowercased())" }
        }
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: body, from: webView)
        controller.flush()

        // Then
        let segments = try core.waitAndReturnEventsData(ofFeature: SessionReplayFeature.name)
            .map { try SegmentJSON($0, source: .ios) }
        let segment = try XCTUnwrap(segments.first)

        let expectedUUID = randomUUID.uuidString.lowercased()
        let expectedSlotID = String(webView.hash)

        XCTAssertEqual(segment.applicationID, randomApplicationID)
        XCTAssertEqual(segment.sessionID, expectedUUID)
        XCTAssertEqual(segment.viewID, randomBrowserViewID.uuidString.lowercased())

        let record = try XCTUnwrap(segment.records.first)
        DDAssertDictionariesEqual(record, [
            "timestamp": 1_635_932_927_012 + 123.toInt64Milliseconds,
            "type": 2,
            "slotId": expectedSlotID
        ])
    }
}

#endif
