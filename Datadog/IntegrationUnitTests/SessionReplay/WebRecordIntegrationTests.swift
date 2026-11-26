/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if os(iOS)
import WebKit

@_spi(Internal)
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogWebViewTracking
@_spi(Internal)
@testable import DatadogSessionReplay

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

    override func tearDownWithError() throws {
        WebViewTracking.disable(webView: webView)
        try core.flushAndTearDown()
        core = nil
        webView = nil
        controller = nil
    }

    func testWebRecordIntegration() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: RUMUUID = .mockRandom()
        let randomBrowserViewID: UUID = .mockRandom()

        let config = SessionReplay.Configuration(
            replaySampleRate: 100,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll,
            touchPrivacyLevel: .show
        )
        SessionReplay.enable(with: config, in: core)
        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        let rumBody = """
        {
            "eventType": "rum",
                "event": {
                    "date": \(1_635_932_927_012),
                    "type": "view",
                    "application": { "id": "\(randomApplicationID)" },
                    "session": { "id": "\(randomUUID.toRUMDataFormat)" },
                    "view": { "id": "\(randomBrowserViewID.uuidString.lowercased())" }
            }
        }
        """

        let body = """
        {
            "eventType": "record",
            "event": {
                "timestamp" : \(1_635_932_927_012),
                "type": 2
            },
            "view": { "id": "\(randomBrowserViewID.uuidString.lowercased())" }
        }
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: rumBody, from: webView)
        controller.flush()
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name) // Wait for context propagation
        controller.send(body: body, from: webView)
        controller.flush()

        // Then
        let segments = try core.waitAndReturnEventsData(ofFeature: SessionReplayFeature.name)
            .map { try SegmentJSON($0, source: .ios) }
        let segment = try XCTUnwrap(segments.first)

        let expectedUUID = randomUUID.toRUMDataFormat
        let expectedSlotID = String(webView.hash)

        XCTAssertEqual(segment.applicationID, randomApplicationID)
        XCTAssertEqual(segment.sessionID, expectedUUID)
        XCTAssertEqual(segment.viewID, randomBrowserViewID.uuidString.lowercased())

        let record = try XCTUnwrap(segment.records.first)
        DDAssertDictionariesEqual(record, [
            "timestamp": 1_635_932_927_012 + 123.dd.toInt64Milliseconds,
            "type": 2,
            "slotId": expectedSlotID
        ])
    }

    @MainActor
    func testExpiredBrowserRecordFollowsTheViewWhenRecordArrivesFirst() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native WebView session capture requires iOS 27")
        }
        try assertExpiredBrowserRecordFollowsView(recordFirst: true)
    }

    @MainActor
    func testExpiredBrowserRecordFollowsTheViewWhenViewArrivesFirst() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native WebView session capture requires iOS 27")
        }
        try assertExpiredBrowserRecordFollowsView(recordFirst: false)
    }

    @MainActor
    func testClearingDataDropsAnExpiredBrowserRecordWaitingForRenewal() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native WebView session capture requires iOS 27")
        }
        try assertExpiredBrowserRecordFollowsView(recordFirst: true, clearBeforeView: true)
    }

    @MainActor
    func testAnUnrelatedNativeSessionCannotAcceptAnExpiredBrowserRecord() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native WebView session capture requires iOS 27")
        }
        try assertExpiredBrowserRecordFollowsView(recordFirst: true, startUnrelatedSession: true)
    }

    @available(iOS 27.0, *)
    @MainActor
    private func assertExpiredBrowserRecordFollowsView(
        recordFirst: Bool,
        clearBeforeView: Bool = false,
        startUnrelatedSession: Bool = false
    ) throws {
        let date = Date()
        let clock = MonotonicClockMock()
        let intake = HTTPClientMock()
        let root = obtainUniqueTemporaryDirectory()
        let sdkDirectory = root.appendingPathComponent("sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: sdkDirectory, withIntermediateDirectories: true)
        let core = DatadogCore(
            directory: CoreDirectory(osDirectory: .init(url: root), coreDirectory: .init(url: sdkDirectory)),
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: intake,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer {
            core.flushAndTearDown()
            try? FileManager.default.removeItem(at: root)
        }
        core.contextProvider.write {
            $0 = .mockWith(
                sdkInitDate: date,
                trackingConsent: .granted,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        let replayScope = FeatureScopeMock()
        try core.register(feature: ReplayReceiverProbe(messageReceiver: WebViewRecordReceiver(scope: replayScope)))
        var configuration = RUM.Configuration(applicationID: "replay-renewal-test")
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        configuration.sessionSampleRate = 100
        configuration.monotonicClock = clock
        configuration.vitalsUpdateFrequency = nil
        try RUM.enableOrThrow(with: configuration, in: core)
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let scene = RUMSceneIdentifier(rawValue: "browser-replay-test-scene")
        feature.monitor.process(command: RUMStartViewCommand(
            time: date,
            identity: ViewIdentifier("native"),
            name: "Native",
            path: "native",
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual,
            target: .scene(scene)
        ))
        core.flush()
        let predecessor = try XCTUnwrap(feature.monitor.rumContextSnapshot(for: .scene(scene)))
        replayScope.contextMock = .mockWith(trackingConsent: .granted, additionalContext: [predecessor])
        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration)
        let observation = try XCTUnwrap(feature.observeRUMSession(forSceneIdentifier: scene.rawValue, owner: owner))
        let expiry = try XCTUnwrap(observation.expiry)
        XCTAssertEqual(expiry.sessionID, predecessor.sessionID)
        let browserView = UUID().uuidString.lowercased()
        func send(_ message: WebViewMessage, slotID: String = "registered-browser") {
            core.send(message: .payload(WebViewMessageWithRUMContext(
                message: message,
                capture: observation.capture,
                sessionExpiry: expiry,
                slotID: slotID
            )))
            core.flush()
        }
        let browserRecord = try JSONDecoder().decode(WebViewMessage.self, from: Data("""
        {
            "eventType": "record",
            "event": { "timestamp": 1700000000000, "type": 2 },
            "view": { "id": "\(browserView)" }
        }
        """.utf8))
        let view: WebViewMessage = .rum([
            "type": "view",
            "date": 1_700_000_000_000,
            "application": ["id": "browser"],
            "session": ["id": "browser"],
            "view": ["id": browserView]
        ])
        if recordFirst {
            send(browserRecord)
            XCTAssertNil(feature.monitor.rumContextSnapshot(for: .processRepresentative), "A record cannot start a session")
            XCTAssertTrue(replayScope.eventsWritten.isEmpty)
        }
        if clearBeforeView {
            core.clearAllData()
            core.flush()
        }
        if startUnrelatedSession {
            feature.monitor.stopSession()
            feature.monitor.startView(key: "unrelated", name: "Unrelated", attributes: [:])
            core.flush()
        }
        send(view)
        let successor = try XCTUnwrap(feature.monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNotEqual(successor.sessionID, predecessor.sessionID)
        replayScope.contextMock = .mockWith(trackingConsent: .granted, additionalContext: [successor])
        if !recordFirst {
            send(browserRecord)
        }
        if !clearBeforeView && !startUnrelatedSession {
            send(browserRecord, slotID: "different-browser")
        }
        core.flushAndUpload()
        let requests = intake.requestsSent()
        let events = try requests.flatMap { request -> [[String: Any]] in
            guard request.url?.path.hasSuffix("/rum") == true, let body = try request.decompressed().httpBody else {
                return []
            }
            return try body.split(separator: 0x0A).compactMap {
                try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
            }
        }
        let matchingViews = events.filter { ($0["view"] as? [String: Any])?["id"] as? String == browserView }
        let records = replayScope.eventsWritten(ofType: WebViewRecordReceiver.WebRecord.self)
        if startUnrelatedSession {
            XCTAssertTrue(matchingViews.isEmpty)
            XCTAssertTrue(records.isEmpty)
            return
        }
        let acceptedView = try XCTUnwrap(matchingViews.first)
        XCTAssertEqual((acceptedView["session"] as? [String: Any])?["id"] as? String, successor.sessionID)
        if clearBeforeView {
            XCTAssertTrue(records.isEmpty)
        } else {
            XCTAssertEqual(records.map(\.viewID), [browserView])
            XCTAssertEqual(records.map(\.sessionID), [successor.sessionID])
        }
    }

    private struct ReplayReceiverProbe: DatadogFeature, DataClearable {
        static let name = "replay-renewal-test-probe"
        let messageReceiver: FeatureMessageReceiver

        func clearAllData() {
            (messageReceiver as? WebViewRecordReceiver)?.clearAllData()
        }
    }

    func testWebRecordIntegrationWithNewSessionReplayConfigurationAPI() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: RUMUUID = .mockRandom()
        let randomBrowserViewID: UUID = .mockRandom()

        SessionReplay.enable(with: SessionReplay.Configuration(
            replaySampleRate: 100,
            textAndInputPrivacyLevel: .mockRandom(),
            imagePrivacyLevel: .mockRandom(),
            touchPrivacyLevel: .mockRandom()
        ), in: core)
        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        let rumBody = """
        {
            "eventType": "rum",
                "event": {
                    "date": \(1_635_932_927_012),
                    "type": "view",
                    "application": { "id": "\(randomApplicationID)" },
                    "session": { "id": "\(randomUUID.toRUMDataFormat)" },
                    "view": { "id": "\(randomBrowserViewID.uuidString.lowercased())" }
            }
        }
        """

        let body = """
        {
            "eventType": "record",
            "event": {
                "timestamp" : \(1_635_932_927_012),
                "type": 2
            },
            "view": { "id": "\(randomBrowserViewID.uuidString.lowercased())" }
        }
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: rumBody, from: webView)
        controller.flush()
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name) // Wait for context propagation
        controller.send(body: body, from: webView)
        controller.flush()

        // Then
        let segments = try core.waitAndReturnEventsData(ofFeature: SessionReplayFeature.name)
            .map { try SegmentJSON($0, source: .ios) }
        let segment = try XCTUnwrap(segments.first)

        let expectedUUID = randomUUID.toRUMDataFormat
        let expectedSlotID = String(webView.hash)

        XCTAssertEqual(segment.applicationID, randomApplicationID)
        XCTAssertEqual(segment.sessionID, expectedUUID)
        XCTAssertEqual(segment.viewID, randomBrowserViewID.uuidString.lowercased())

        let record = try XCTUnwrap(segment.records.first)
        DDAssertDictionariesEqual(record, [
            "timestamp": 1_635_932_927_012 + 123.dd.toInt64Milliseconds,
            "type": 2,
            "slotId": expectedSlotID
        ])
    }
}

#endif
