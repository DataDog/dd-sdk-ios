/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogLogs
@_spi(objc)
@testable import DatadogCore

/// These tests verify that Objc APIs properly interact with`Datadog` public API (swift).
class DDDatadogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertFalse(Datadog.isInitialized())
    }

    override func tearDown() {
        XCTAssertFalse(Datadog.isInitialized())
        super.tearDown()
    }

    // MARK: - SDK initialization / stop lifecycle

    func testItForwardsInitializationToSwift() throws {
        let config = objc_Configuration(
            clientToken: "abcefghi",
            env: "tests"
        )

        config.bundle = .mockWith(CFBundleExecutable: "app-name")

        objc_Datadog.initialize(
            configuration: config,
            trackingConsent: randomConsent().objc
        )

        XCTAssertTrue(Datadog.isInitialized())

        let context = try XCTUnwrap(CoreRegistry.default as? DatadogCore).contextProvider.read()
        XCTAssertEqual(context.applicationName, "app-name")
        XCTAssertEqual(context.env, "tests")

        Datadog.flushAndDeinitialize()

        XCTAssertNil(CoreRegistry.default.get(feature: LogsFeature.self))
    }

    func testItReflectsInitializationStatus() throws {
        let config = objc_Configuration(
            clientToken: "abcefghi",
            env: "tests"
        )

        config.bundle = .mockWith(CFBundleExecutable: "app-name")
        XCTAssertFalse(objc_Datadog.isInitialized())

        objc_Datadog.initialize(
            configuration: config,
            trackingConsent: randomConsent().objc
        )

        XCTAssertTrue(objc_Datadog.isInitialized())

        Datadog.flushAndDeinitialize()

        XCTAssertNil(CoreRegistry.default.get(feature: LogsFeature.self))
    }

    func testItForwardsStopInstanceToSwift() throws {
        let config = objc_Configuration(
            clientToken: "abcefghi",
            env: "tests"
        )

        config.bundle = .mockWith(CFBundleExecutable: "app-name")

        objc_Datadog.initialize(
            configuration: config,
            trackingConsent: randomConsent().objc
        )

        XCTAssertTrue(Datadog.isInitialized())

        objc_Datadog.stopInstance()

        XCTAssertFalse(Datadog.isInitialized())

        XCTAssertNil(CoreRegistry.default.get(feature: LogsFeature.self))
    }

    // MARK: - Changing Tracking Consent

    func testItForwardsTrackingConsentToSwift() {
        let initialConsent = randomConsent()
        let nextConsent = randomConsent()

        objc_Datadog.initialize(
            configuration: objc_Configuration(clientToken: "abcefghi", env: "tests"),
            trackingConsent: initialConsent.objc
        )

        let core = CoreRegistry.default as? DatadogCore
        XCTAssertEqual(core?.consentPublisher.consent, initialConsent.swift)

        objc_Datadog.setTrackingConsent(consent: nextConsent.objc)

        XCTAssertEqual(core?.consentPublisher.consent, nextConsent.swift)

        Datadog.flushAndDeinitialize()
    }

    // MARK: - Setting user info

    func testItForwardsUserInfoToSwift() throws {
        objc_Datadog.initialize(
            configuration: objc_Configuration(clientToken: "abcefghi", env: "tests"),
            trackingConsent: randomConsent().objc
        )

        let core = CoreRegistry.default as? DatadogCore
        let userInfo = try XCTUnwrap(core?.userInfoPublisher)

        objc_Datadog.setUserInfo(
            userId: "id",
            name: "name",
            email: "email",
            extraInfo: [
                "attribute-int": 42,
                "attribute-double": 42.5,
                "attribute-string": "string value"
            ]
        )
        objc_Datadog.addUserExtraInfo(["foo": "bar"])
        XCTAssertEqual(userInfo.current.id, "id")
        XCTAssertEqual(userInfo.current.name, "name")
        XCTAssertEqual(userInfo.current.email, "email")
        let extraInfo = userInfo.current.extraInfo
        XCTAssertEqual(extraInfo["attribute-int"]?.dd.decode(), 42)
        XCTAssertEqual(extraInfo["attribute-double"]?.dd.decode(), 42.5)
        XCTAssertEqual(extraInfo["attribute-string"]?.dd.decode(), "string value")
        XCTAssertEqual(extraInfo["foo"]?.dd.decode(), "bar")

        objc_Datadog.setUserInfo(userId: "id", name: nil, email: nil, extraInfo: [:])
        XCTAssertNotNil(userInfo.current.id)
        XCTAssertNil(userInfo.current.name)
        XCTAssertNil(userInfo.current.email)
        XCTAssertTrue(userInfo.current.extraInfo.isEmpty)

        XCTAssertEqual(objc_Datadog.currentUserId(), "id")

        Datadog.flushAndDeinitialize()
    }

    func testItReturnsCurrentUserAndAccountIdsFromObjcAPI() throws {
        objc_Datadog.initialize(
            configuration: objc_Configuration(clientToken: "abcefghi", env: "tests"),
            trackingConsent: randomConsent().objc
        )

        objc_Datadog.setUserInfo(userId: "user-id", name: nil, email: nil, extraInfo: [:])
        objc_Datadog.setAccountInfo(accountId: "account-id", name: nil, extraInfo: [:])

        XCTAssertEqual(objc_Datadog.currentUserId(), "user-id")
        XCTAssertEqual(objc_Datadog.currentAccountId(), "account-id")

        objc_Datadog.clearUserInfo()
        objc_Datadog.clearAccountInfo()

        XCTAssertNil(objc_Datadog.currentUserId())
        XCTAssertNil(objc_Datadog.currentAccountId())

        Datadog.flushAndDeinitialize()
    }

    // MARK: - Changing SDK verbosity level

    private let swiftVerbosityLevels: [CoreLoggerLevel?] = [
        .debug, .warn, .error, .critical, nil
    ]
    private let objcVerbosityLevels: [objc_CoreLoggerLevel] = [
        .debug, .warn, .error, .critical, .none
    ]

    func testItForwardsSettingVerbosityLevelToSwift() {
        defer { Datadog.verbosityLevel = nil }

        zip(swiftVerbosityLevels, objcVerbosityLevels).forEach { swiftLevel, objcLevel in
            objc_Datadog.setVerbosityLevel(objcLevel)
            XCTAssertEqual(Datadog.verbosityLevel, swiftLevel)
        }
    }

    func testItGetsVerbosityLevelFromSwift() {
        defer { Datadog.verbosityLevel = nil }

        zip(swiftVerbosityLevels, objcVerbosityLevels).forEach { swiftLevel, objcLevel in
            Datadog.verbosityLevel = swiftLevel
            XCTAssertEqual(objc_Datadog.verbosityLevel(), objcLevel)
        }
    }

    // MARK: - Helpers

    private func randomConsent() -> (objc: objc_TrackingConsent, swift: TrackingConsent) {
        let objcConsents: [objc_TrackingConsent] = [.granted(), .notGranted(), .pending()]
        let swiftConsents: [TrackingConsent] = [.granted, .notGranted, .pending]
        let index: Int = .random(in: 0..<3)
        return (objc: objcConsents[index], swift: swiftConsents[index])
    }
}
