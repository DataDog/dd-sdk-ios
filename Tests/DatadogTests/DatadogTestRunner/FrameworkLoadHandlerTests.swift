/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FrameworkLoadHandlerTests: XCTestCase {
    var testEnvironment = [String: String]()

    override func setUp() {
        FrameworkLoadHandler.environment = [String: String]()
        DDTestRunner.instance = nil
    }

    override func tearDownWithError() throws {
        if let observer = DDTestRunner.instance {
            XCTestObservationCenter.shared.removeTestObserver(observer)
            DDTestRunner.instance = nil
        }

        if Datadog.instance != nil {
            try Datadog.deinitializeOrThrow()
        }
    }

    func setEnvVariables() {
        FrameworkLoadHandler.environment = testEnvironment
    }

    func testTestRunnerInitialisedIfConfiguredAndTesting() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["XCTestConfigurationFilePath"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestRunner.instance)
    }

    func testTestRunnerInitialisedIfConfiguredAndTestingOther() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNotNil(DDTestRunner.instance)
    }

    func testNoTestRunnerIfNotConfigured() {
        testEnvironment["XCInjectBundleInto"] = "/Users/user/Library/tmp/xx.xctestconfiguration"
        setEnvVariables()

        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestRunner.instance)
    }

    func testNoTestRunnerIfConfiguredButNotTesting() {
        testEnvironment["DD_TEST_RUNNER"] = "1"
        setEnvVariables()
        FrameworkLoadHandler.handleLoad()

        XCTAssertNil(DDTestRunner.instance)
    }
}
