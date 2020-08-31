/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogTests: XCTestCase {
    private var printFunction: PrintFunctionMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var defaultBuilder: Datadog.Configuration.Builder {
        Datadog.Configuration.builderUsing(clientToken: "abc-123", environment: "tests")
    }
    private var rumBuilder: Datadog.Configuration.Builder {
        Datadog.Configuration.builderUsing(rumApplicationID: "rum-123", clientToken: "abc-123", environment: "tests")
    }

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

    // MARK: - Initializing with different configurations

    func testGivenDefaultConfiguration_itCanBeInitialized() throws {
        Datadog.initialize(appContext: .mockAny(), configuration: defaultBuilder.build())
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testGivenDefaultRUMConfiguration_itCanBeInitialized() throws {
        Datadog.initialize(appContext: .mockAny(), configuration: rumBuilder.build())
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testGivenInvalidConfiguration_itPrintsError() throws {
        let invalidConiguration = Datadog.Configuration
            .builderUsing(clientToken: "", environment: "tests")
            .build()

        Datadog.initialize(appContext: .mockAny(), configuration: invalidConiguration)

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `clientToken` cannot be empty."
        )
        XCTAssertNil(Datadog.instance)
    }

    func testGivenValidConfiguration_whenInitializedMoreThanOnce_itPrintsError() throws {
        Datadog.initialize(appContext: .mockAny(), configuration: defaultBuilder.build())
        Datadog.initialize(appContext: .mockAny(), configuration: rumBuilder.build())

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK is already initialized."
        )

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Toggling features

    func testEnablingAndDisablingFeatures() throws {
        func verify(configuration: Datadog.Configuration, verificationBlock: () -> Void) throws {
            Datadog.initialize(appContext: .mockAny(), configuration: configuration)
            verificationBlock()
            try Datadog.deinitializeOrThrow()
        }

        defer {
            TracingAutoInstrumentation.instance?.swizzler.unswizzle()
        }

        try verify(configuration: defaultBuilder.build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNil(RUMFeature.instance, "When using `defaultBuilder` RUM feature should be disabled by default")
            XCTAssertNil(TracingAutoInstrumentation.instance)
            // verify integrations:
            XCTAssertNotNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }
        try verify(configuration: rumBuilder.build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNotNil(RUMFeature.instance, "When using `rumBuilder` RUM feature should be enabled by default")
            XCTAssertNil(TracingAutoInstrumentation.instance)
            // verify integrations:
            XCTAssertNotNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }

        try verify(configuration: defaultBuilder.enableLogging(false).build()) {
            // verify features:
            XCTAssertNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNil(RUMFeature.instance, "When using `defaultBuilder` RUM feature should be disabled by default")
            XCTAssertNil(TracingAutoInstrumentation.instance)
            // verify integrations:
            XCTAssertNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }
        try verify(configuration: rumBuilder.enableLogging(false).build()) {
            // verify features:
            XCTAssertNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNotNil(RUMFeature.instance, "When using `rumBuilder` RUM feature should be enabled by default")
            XCTAssertNil(TracingAutoInstrumentation.instance)
            // verify integrations:
            XCTAssertNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }

        try verify(configuration: defaultBuilder.enableTracing(false).build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNil(TracingFeature.instance)
            XCTAssertNil(RUMFeature.instance, "When using `defaultBuilder` RUM feature should be disabled by default")
            // verify integrations:
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }
        try verify(configuration: rumBuilder.enableTracing(false).build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNil(TracingFeature.instance)
            XCTAssertNotNil(RUMFeature.instance, "When using `rumBuilder` RUM feature should be enabled by default")
            // verify integrations:
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }

        try verify(configuration: defaultBuilder.enableRUM(true).build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNil(RUMFeature.instance, "When using `defaultBuilder` RUM feature cannot be enabled")
            // verify integrations:
            XCTAssertNotNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }
        try verify(configuration: rumBuilder.enableRUM(false).build()) {
            // verify features:
            XCTAssertNotNil(LoggingFeature.instance)
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNil(RUMFeature.instance)
            // verify integrations:
            XCTAssertNotNil(TracingFeature.instance?.loggingFeatureAdapter)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }

        try verify(configuration: defaultBuilder.set(tracedHosts: ["example.com"]).build()) {
            XCTAssertNotNil(TracingFeature.instance)
            XCTAssertNotNil(TracingAutoInstrumentation.instance)
        }
        try verify(
            configuration: defaultBuilder.enableTracing(false).set(tracedHosts: ["example.com"]).build()
        ) {
            XCTAssertNil(TracingFeature.instance)
            XCTAssertNil(TracingAutoInstrumentation.instance)
        }
    }

    // MARK: - Defaults

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }

    func testDefaultUserInfo() throws {
        Datadog.initialize(appContext: .mockAny(), configuration: defaultBuilder.build())

        XCTAssertNotNil(Datadog.instance?.userInfoProvider.value)
        XCTAssertNil(Datadog.instance?.userInfoProvider.value.id)
        XCTAssertNil(Datadog.instance?.userInfoProvider.value.email)
        XCTAssertNil(Datadog.instance?.userInfoProvider.value.name)

        try Datadog.deinitializeOrThrow()
    }

    func testDefaultDebugRUM() {
        XCTAssertFalse(Datadog.debugRUM)
    }
}

class AppContextTests: XCTestCase {
    func testBundleType() {
        let iOSAppBundle: Bundle = .mockWith(bundlePath: "mock.app")
        let iOSAppExtensionBundle: Bundle = .mockWith(bundlePath: "mock.appex")
        XCTAssertEqual(AppContext(mainBundle: iOSAppBundle).bundleType, .iOSApp)
        XCTAssertEqual(AppContext(mainBundle: iOSAppExtensionBundle).bundleType, .iOSAppExtension)
    }

    func testBundleIdentifier() throws {
        XCTAssertEqual(AppContext(mainBundle: .mockWith(bundleIdentifier: "com.abc.app")).bundleIdentifier, "com.abc.app")
        XCTAssertNil(AppContext(mainBundle: .mockWith(bundleIdentifier: nil)).bundleIdentifier)
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
        XCTAssertNil(
            AppContext(mainBundle: .mockWith(CFBundleVersion: nil, CFBundleShortVersionString: nil)).bundleVersion
        )
    }

    func testBundleName() throws {
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(bundlePath: .mockAny(), CFBundleExecutable: "FooApp")).bundleName,
            "FooApp"
        )
    }
}
