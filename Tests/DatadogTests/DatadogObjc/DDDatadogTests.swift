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
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        super.tearDown()
    }

    // MARK: - Initializing with configuration

    func testItFowardsInitializationToSwift() throws {
        DDDatadog.initialize(
            appContext: .mockAny(),
            configuration: DDConfiguration.builder(clientToken: "abcefghi").build()
        )

        XCTAssertNotNil(Datadog.instance)

        try Datadog.deinitializeOrThrow()
    }

    func testItBuildsDefaultSwiftAppContext() throws {
        DDDatadog.initialize(appContext: .init(), configuration: .mockAny())

        let objcAppContext = LoggingFeature.instance?.appContext
        let swiftAppContext = Datadog.AppContext()

        XCTAssertEqual(objcAppContext?.bundleIdentifier, swiftAppContext.bundleIdentifier)
        XCTAssertEqual(objcAppContext?.bundleVersion, swiftAppContext.bundleVersion)
        XCTAssertEqual(objcAppContext?.bundleShortVersion, swiftAppContext.bundleShortVersion)
        XCTAssertEqual(objcAppContext?.executableName, swiftAppContext.executableName)
        XCTAssertEqual(objcAppContext?.mobileDevice != nil, swiftAppContext.mobileDevice != nil)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Setting user info

    func testItForwardsUserInfoToSwift() throws {
        DDDatadog.initialize(appContext: .init(), configuration: .mockAny())
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
}
