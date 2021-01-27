/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import Datadog
import DatadogObjc

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDDatadogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
        super.tearDown()
    }

    // MARK: - Initializing with configuration

    func testItFowardsInitializationToSwift() throws {
        let configBuilder = DDConfiguration.builder(clientToken: "abcefghi", environment: "tests")
        configBuilder.trackURLSession(firstPartyHosts: ["example.com"])

        DDDatadog.initialize(
            appContext: DDAppContext(mainBundle: BundleMock.mockWith(CFBundleExecutable: "app-name")),
            trackingConsent: randomConsent().objc,
            configuration: configBuilder.build()
        )

        XCTAssertNotNil(Datadog.instance)
        XCTAssertEqual(LoggingFeature.instance?.configuration.common.applicationName, "app-name")
        XCTAssertEqual(LoggingFeature.instance?.configuration.common.environment, "tests")
        XCTAssertNotNil(URLSessionAutoInstrumentation.instance)

        URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Changing Tracking Consent

    func testItForwardsTrackingConsentToSwift() throws {
        let initialConsent = randomConsent()
        let nextConsent = randomConsent()

        DDDatadog.initialize(
            appContext: .init(),
            trackingConsent: initialConsent.objc,
            configuration: DDConfiguration.builder(clientToken: "abcefghi", environment: "tests").build()
        )

        XCTAssertEqual(Datadog.instance?.consentProvider.currentValue, initialConsent.swift)

        DDDatadog.setTrackingConsent(consent: nextConsent.objc)

        XCTAssertEqual(Datadog.instance?.consentProvider.currentValue, nextConsent.swift)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Setting user info

    func testItForwardsUserInfoToSwift() throws {
        DDDatadog.initialize(
            appContext: .init(),
            trackingConsent: randomConsent().objc,
            configuration: DDConfiguration.builder(clientToken: "abcefghi", environment: "tests").build()
        )
        let userInfo = Datadog.instance?.userInfoProvider

        DDDatadog.setUserInfo(id: "id", name: "name", email: "email")
        XCTAssertEqual(userInfo?.value.id, "id")
        XCTAssertEqual(userInfo?.value.name, "name")
        XCTAssertEqual(userInfo?.value.email, "email")

        DDDatadog.setUserInfo(id: nil, name: nil, email: nil)
        XCTAssertNil(userInfo?.value.id)
        XCTAssertNil(userInfo?.value.name)
        XCTAssertNil(userInfo?.value.email)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Changing SDK verbosity level

    private let swiftVerbosityLevels: [LogLevel?] = [
        .debug, .info, .notice, .warn, .error, .critical, nil
    ]
    private let objcVerbosityLevels: [DDSDKVerbosityLevel] = [
        .debug, .info, .notice, .warn, .error, .critical, .none
    ]

    func testItForwardsSettingVerbosityLevelToSwift() {
        defer { Datadog.verbosityLevel = nil }

        zip(swiftVerbosityLevels, objcVerbosityLevels).forEach { swiftLevel, objcLevel in
            DDDatadog.setVerbosityLevel(objcLevel)
            XCTAssertEqual(Datadog.verbosityLevel, swiftLevel)
        }
    }

    func testItGetsVerbosityLevelFromSwift() {
        defer { Datadog.verbosityLevel = nil }

        zip(swiftVerbosityLevels, objcVerbosityLevels).forEach { swiftLevel, objcLevel in
            Datadog.verbosityLevel = swiftLevel
            XCTAssertEqual(DDDatadog.verbosityLevel(), objcLevel)
        }
    }

    // MARK: - Helpers

    private func randomConsent() -> (objc: DDTrackingConsent, swift: TrackingConsent) {
        let objcConsents: [DDTrackingConsent] = [.granted(), .notGranted(), .pending()]
        let swiftConsents: [TrackingConsent] = [.granted, .notGranted, .pending]
        let index: Int = .random(in: 0..<3)
        return (objc: objcConsents[index], swift: swiftConsents[index])
    }
}
