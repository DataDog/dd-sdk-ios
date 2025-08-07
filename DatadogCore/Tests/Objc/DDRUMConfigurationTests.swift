/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogRUM

class DDRUMConfigurationTests: XCTestCase {
    private var objc = objc_RUMConfiguration(applicationID: "app-id")
    private var swift: RUM.Configuration { objc.swiftConfig }

    func testApplicationID() {
        objc = objc_RUMConfiguration(applicationID: "rum-app-id")
        XCTAssertEqual(swift.applicationID, "rum-app-id")
    }

    func testSessionSampleRate() {
        objc.sessionSampleRate = 30
        XCTAssertEqual(objc.sessionSampleRate, 30)
        XCTAssertEqual(swift.sessionSampleRate, 30)
    }

    func testTelemetrySampleRate() {
        objc.telemetrySampleRate = 30
        XCTAssertEqual(objc.telemetrySampleRate, 30)
        XCTAssertEqual(swift.telemetrySampleRate, 30)
    }

    func testUIKitViewsPredicate() {
        class ObjcPredicate: objc_UIKitRUMViewsPredicate {
            func rumView(for viewController: UIViewController) -> objc_RUMView? { nil }
        }
        let predicate = ObjcPredicate()
        objc.uiKitViewsPredicate = predicate
        XCTAssertIdentical(objc.uiKitViewsPredicate, predicate)
        XCTAssertNotNil(swift.uiKitViewsPredicate)
    }

    func testUIKitActionsPredicate() {
        class ObjcPredicate: objc_UIKitRUMActionsPredicate & objc_UITouchRUMActionsPredicate & objc_UIPressRUMActionsPredicate {
            func rumAction(targetView: UIView) -> objc_RUMAction? { nil }
            func rumAction(press type: UIPress.PressType, targetView: UIView) -> objc_RUMAction? { nil }
        }
        let predicate = ObjcPredicate()
        objc.uiKitActionsPredicate = predicate
        XCTAssertIdentical(objc.uiKitActionsPredicate, predicate)
        XCTAssertNotNil(swift.uiKitActionsPredicate)
    }

    func testSetDDRUMURLSessionTrackingWithFirstPartyHosts() {
        let tracking = objc_URLSessionTracking()

        objc.setURLSessionTracking(tracking)
        DDAssertReflectionEqual(swift.urlSessionTracking, RUM.Configuration.URLSessionTracking())

        tracking.setFirstPartyHostsTracing(.init(hosts: ["foo.com"]))
        objc.setURLSessionTracking(tracking)
        DDAssertReflectionEqual(swift.urlSessionTracking, .init(firstPartyHostsTracing: .trace(hosts: ["foo.com"])))

        tracking.setFirstPartyHostsTracing(.init(hosts: ["foo.com"], sampleRate: 99))
        objc.setURLSessionTracking(tracking)
        DDAssertReflectionEqual(swift.urlSessionTracking, .init(firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: 99)))

        tracking.setFirstPartyHostsTracing(.init(hostsWithHeaderTypes: ["foo.com": [.b3, .datadog]]))
        objc.setURLSessionTracking(tracking)
        DDAssertReflectionEqual(swift.urlSessionTracking, .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: ["foo.com": [.b3, .datadog]])))

        tracking.setFirstPartyHostsTracing(.init(hostsWithHeaderTypes: ["foo.com": [.b3, .datadog]], sampleRate: 99))
        objc.setURLSessionTracking(tracking)
        DDAssertReflectionEqual(swift.urlSessionTracking, .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: ["foo.com": [.b3, .datadog]], sampleRate: 99)))
    }

    func testSetDDRUMURLSessionTrackingWithResourceAttributesProvider() {
        let tracking = objc_URLSessionTracking()

        objc.setURLSessionTracking(tracking)
        XCTAssertNil(swift.urlSessionTracking?.resourceAttributesProvider)

        tracking.setResourceAttributesProvider { _, _, _, _ in nil }
        objc.setURLSessionTracking(tracking)
        XCTAssertNotNil(swift.urlSessionTracking?.resourceAttributesProvider)
    }

    func testFrustrationsTracking() {
        let random: Bool = .mockRandom()
        objc.trackFrustrations = random
        XCTAssertEqual(objc.trackFrustrations, random)
        XCTAssertEqual(swift.trackFrustrations, random)
    }

    func testBackgroundEventsTracking() {
        let random: Bool = .mockRandom()
        objc.trackBackgroundEvents = random
        XCTAssertEqual(objc.trackBackgroundEvents, random)
        XCTAssertEqual(swift.trackBackgroundEvents, random)
    }

    func testLongTaskThreshold() {
        let random: TimeInterval = .mockRandom()
        objc.longTaskThreshold = random
        XCTAssertEqual(objc.longTaskThreshold, random)
        XCTAssertEqual(swift.longTaskThreshold, random)
    }

    func testAppHangThreshold() {
        let random: TimeInterval = .mockRandom(min: 0.01, max: .greatestFiniteMagnitude)
        objc.appHangThreshold = random
        XCTAssertEqual(objc.appHangThreshold, random)
        XCTAssertEqual(swift.appHangThreshold, random)
    }

    func testAppHangThresholdDisable() {
        objc.appHangThreshold = 0
        XCTAssertEqual(objc.appHangThreshold, 0)
        XCTAssertEqual(swift.appHangThreshold, nil)
    }

    func testVitalsUpdateFrequency() {
        objc.vitalsUpdateFrequency = .frequent
        XCTAssertEqual(swift.vitalsUpdateFrequency, .frequent)

        objc.vitalsUpdateFrequency = .never
        XCTAssertNil(swift.vitalsUpdateFrequency)
    }

    func testEventMappers() {
        let swiftViewEvent: RUMViewEvent = .mockRandom()
        let swiftResourceEvent: RUMResourceEvent = .mockRandom()
        let swiftActionEvent: RUMActionEvent = .mockAny()
        let swiftErrorEvent: RUMErrorEvent = .mockRandom()
        let swiftLongTaskEvent: RUMLongTaskEvent = .mockRandom()

        objc.setViewEventMapper { objcViewEvent in
            DDAssertReflectionEqual(objcViewEvent.swiftModel, swiftViewEvent)
            objcViewEvent.view.url = "redacted view.url"
            return objcViewEvent
        }

        objc.setResourceEventMapper { objcResourceEvent in
            DDAssertReflectionEqual(objcResourceEvent.swiftModel, swiftResourceEvent)
            objcResourceEvent.view.url = "redacted view.url"
            objcResourceEvent.resource.url = "redacted resource.url"
            return objcResourceEvent
        }

        objc.setActionEventMapper { objcActionEvent in
            DDAssertReflectionEqual(objcActionEvent.swiftModel, swiftActionEvent)
            objcActionEvent.view.url = "redacted view.url"
            objcActionEvent.action.target?.name = "redacted action.target.name"
            return objcActionEvent
        }

        objc.setErrorEventMapper { objcErrorEvent in
            DDAssertReflectionEqual(objcErrorEvent.swiftModel, swiftErrorEvent)
            objcErrorEvent.view.url = "redacted view.url"
            objcErrorEvent.error.message = "redacted error.message"
            objcErrorEvent.error.resource?.url = "redacted error.resource.url"
            return objcErrorEvent
        }

        objc.setLongTaskEventMapper { objcLongTaskEvent in
            DDAssertReflectionEqual(objcLongTaskEvent.swiftModel, swiftLongTaskEvent)
            objcLongTaskEvent.view.url = "redacted view.url"
            return objcLongTaskEvent
        }

        let redactedSwiftViewEvent = swift.viewEventMapper?(swiftViewEvent)
        let redactedSwiftResourceEvent = swift.resourceEventMapper?(swiftResourceEvent)
        let redactedSwiftActionEvent = swift.actionEventMapper?(swiftActionEvent)
        let redactedSwiftErrorEvent = swift.errorEventMapper?(swiftErrorEvent)
        let redactedSwiftLongTaskEvent = swift.longTaskEventMapper?(swiftLongTaskEvent)

        XCTAssertEqual(redactedSwiftViewEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.resource.url, "redacted resource.url")
        XCTAssertEqual(redactedSwiftActionEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftActionEvent?.action.target?.name, "redacted action.target.name")
        XCTAssertEqual(redactedSwiftErrorEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.message, "redacted error.message")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.resource?.url, "redacted error.resource.url")
        XCTAssertEqual(redactedSwiftLongTaskEvent?.view.url, "redacted view.url")
    }

    func testOnSessionStart() {
        objc.onSessionStart = { _, _ in }
        XCTAssertNotNil(swift.onSessionStart)
    }

    func testCustomEndpoint() {
        let random: URL = .mockRandom()
        objc.customEndpoint = random
        XCTAssertEqual(objc.customEndpoint, random)
        XCTAssertEqual(swift.customEndpoint, random)
    }
}
