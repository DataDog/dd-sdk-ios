/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogConfigurationTests: XCTestCase {
    private typealias Configuration = Datadog.Configuration

    func testDefaultConfiguration() {
        let defaultConfiguration = Configuration.builderUsing(clientToken: "abcd").build()
        XCTAssertEqual(defaultConfiguration.clientToken, "abcd")
        XCTAssertEqual(defaultConfiguration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")
    }

    // MARK: - Logs endpoint
    func testUSLogsEndpoint() {
        let configuration = Configuration.builderUsing(clientToken: .mockAny()).set(logsEndpoint: .us).build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")
    }

    func testEULogsEndpoint() {
        let configuration = Configuration.builderUsing(clientToken: .mockAny()).set(logsEndpoint: .eu).build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.eu/v1/input/")
    }

    func testCustomLogsEndpoint() {
        let configuration = Configuration.builderUsing(clientToken: .mockAny())
            .set(logsEndpoint: .custom(url: "https://api.example.com/v1/logs/"))
            .build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://api.example.com/v1/logs/")
    }
}

class AppContextTests: XCTestCase {
    func testEnvironment() {
        let iOSAppBundle: Bundle = .mockWith(bundlePath: "mock.app")
        let iOSAppExtensionBundle: Bundle = .mockWith(bundlePath: "mock.appex")
        XCTAssertEqual(AppContext(mainBundle: iOSAppBundle).environment, .iOSApp)
        XCTAssertEqual(AppContext(mainBundle: iOSAppExtensionBundle).environment, .iOSAppExtension)
    }

    func testBundleIdentifier() throws {
        XCTAssertEqual(AppContext(mainBundle: .mockWith(bundleIdentifier: "com.abc.app")).bundleIdentifier, "com.abc.app")
        XCTAssertEqual(AppContext(mainBundle: .mockWith(bundleIdentifier: nil)).bundleIdentifier, "unknown")
    }

    func testBundleVersion() throws {
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(CFBundleVersion: "1.0", CFBundleShortVersionString: "1.0.0")).bundleVersion,
            "1.0.0"
        )
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(CFBundleVersion: nil, CFBundleShortVersionString: "1.0.0")).bundleVersion,
            "1.0.0"
        )
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(CFBundleVersion: "1.0", CFBundleShortVersionString: nil)).bundleVersion,
            "1.0"
        )
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(CFBundleVersion: nil, CFBundleShortVersionString: nil)).bundleVersion,
            "0.0.0"
        )
    }

    func testBundleName() throws {
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(bundlePath: .mockAny(), CFBundleExecutable: "FooApp")).bundleName,
            "FooApp"
        )
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(bundlePath: "mock.app", CFBundleExecutable: nil)).bundleName,
            "iOSApp"
        )
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(bundlePath: "mock.appex", CFBundleExecutable: nil)).bundleName,
            "iOSAppExtension"
        )
    }

    func testMobileDevice() throws {
        let context = AppContext(mainBundle: .main)
        XCTAssertTrue((context.mobileDevice == nil) == (MobileDevice.current == nil))
    }
}

class DatadogTests: XCTestCase {
    private var printFunction: PrintFunctionMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private typealias Config = Datadog.Configuration

    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { print($0) }
        printFunction = nil
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    // MARK: - Initializing with configuration

    func testGivenValidConfiguration_itCanBeInitialized() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abcdefghi").build()
        )
        XCTAssertNotNil(Datadog.instance)
        XCTAssertNoThrow(try Datadog.deinitializeOrThrow())
    }

    func testGivenInvalidLogsUploadURL_whenInitializing_itPrintsError() throws {
        Datadog.verbosityLevel = .debug
        defer { Datadog.verbosityLevel = nil }

        let invalidConfig = Config(clientToken: "", logsEndpoint: .us)
        Datadog.initialize(appContext: .mockAny(), configuration: invalidConfig)

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `clientToken` cannot be empty."
        )
        XCTAssertNil(Datadog.instance)
    }

    func testGivenVerbosityLevelSetToLowest_whenInitializingDatadogMoreThanOnce_itPrintsError() throws {
        Datadog.verbosityLevel = .debug
        defer { Datadog.verbosityLevel = nil }

        let mockConfig = Config(clientToken: "mockClientToken", logsEndpoint: .us)
        Datadog.initialize(appContext: .mockAny(), configuration: mockConfig)
        Datadog.initialize(appContext: .mockAny(), configuration: mockConfig)

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK is already initialized."
        )

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Defaults

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }
}
