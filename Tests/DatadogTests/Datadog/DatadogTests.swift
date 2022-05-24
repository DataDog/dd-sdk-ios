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

        XCTAssertFalse(Datadog.isInitialized)
        printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { print($0) }
        printFunction = nil
        XCTAssertFalse(Datadog.isInitialized)
        super.tearDown()
    }

    // MARK: - Initializing with different configurations

    func testGivenDefaultConfiguration_itCanBeInitialized() {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: defaultBuilder.build()
        )
        XCTAssertTrue(Datadog.isInitialized)
        Datadog.flushAndDeinitialize()
    }

    func testGivenDefaultRUMConfiguration_itCanBeInitialized() {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: rumBuilder.build()
        )
        XCTAssertTrue(Datadog.isInitialized)
        Datadog.flushAndDeinitialize()
    }

    func testGivenInvalidConfiguration_itPrintsError() {
        let invalidConfiguration = Datadog.Configuration
            .builderUsing(clientToken: "", environment: "tests")
            .build()

        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: invalidConfiguration
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `clientToken` cannot be empty."
        )
        XCTAssertFalse(Datadog.isInitialized)
    }

    func testGivenValidConfiguration_whenInitializedMoreThanOnce_itPrintsError() {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: defaultBuilder.build()
        )
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: rumBuilder.build()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: SDK is already initialized."
        )

        Datadog.flushAndDeinitialize()
    }

    // MARK: - Toggling features

    func testEnablingAndDisablingFeatures() {
        func verify(configuration: Datadog.Configuration, verificationBlock: () -> Void) {
            Datadog.initialize(
                appContext: .mockAny(),
                trackingConsent: .mockRandom(),
                configuration: configuration
            )
            verificationBlock()

            defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler?.unswizzle()
            URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
            Datadog.flushAndDeinitialize()
        }

        defer {
            defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler?.unswizzle()
            URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
        }

        verify(configuration: defaultBuilder.build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self), "When using `defaultBuilder` RUM feature should be disabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNotNil(tracing?.loggingFeatureAdapter)
        }
        verify(configuration: rumBuilder.build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNotNil(defaultDatadogCore.feature(RUMFeature.self), "When using `rumBuilder` RUM feature should be enabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNotNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNotNil(tracing?.loggingFeatureAdapter)
        }

        verify(configuration: defaultBuilder.enableLogging(false).build()) {
            // verify features:
            XCTAssertNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self), "When using `defaultBuilder` RUM feature should be disabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNil(tracing?.loggingFeatureAdapter)
        }
        verify(configuration: rumBuilder.enableLogging(false).build()) {
            // verify features:
            XCTAssertNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNotNil(defaultDatadogCore.feature(TracingFeature.self))
            XCTAssertNotNil(defaultDatadogCore.feature(RUMFeature.self), "When using `rumBuilder` RUM feature should be enabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNotNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNil(tracing?.loggingFeatureAdapter)
        }

        verify(configuration: defaultBuilder.enableTracing(false).build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(TracingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self), "When using `defaultBuilder` RUM feature should be disabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
        }
        verify(configuration: rumBuilder.enableTracing(false).build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(TracingFeature.self))
            XCTAssertNotNil(defaultDatadogCore.feature(RUMFeature.self), "When using `rumBuilder` RUM feature should be enabled by default")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNotNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
        }

        verify(configuration: defaultBuilder.enableRUM(true).build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self), "When using `defaultBuilder` RUM feature cannot be enabled")
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNotNil(tracing?.loggingFeatureAdapter)
        }
        verify(configuration: rumBuilder.enableRUM(false).build()) {
            // verify features:
            XCTAssertNotNil(defaultDatadogCore.feature(LoggingFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self))
            XCTAssertFalse(CrashReportingFeature.isEnabled)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self))
            XCTAssertNil(URLSessionAutoInstrumentation.instance)
            // verify integrations:
            let tracing = defaultDatadogCore.feature(TracingFeature.self)
            XCTAssertNotNil(tracing)
            XCTAssertNotNil(tracing?.loggingFeatureAdapter)
        }

        verify(configuration: rumBuilder.trackUIKitRUMViews().build()) {
            XCTAssertNotNil(defaultDatadogCore.feature(RUMFeature.self))
            XCTAssertNotNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.userActionsAutoInstrumentation)
        }
        verify(
            configuration: rumBuilder.enableRUM(false).trackUIKitRUMViews().build()
        ) {
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.userActionsAutoInstrumentation)
        }

        verify(configuration: rumBuilder.trackUIKitRUMActions().build()) {
            XCTAssertNotNil(defaultDatadogCore.feature(RUMFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler)
            XCTAssertNotNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.userActionsAutoInstrumentation)
        }
        verify(
            configuration: rumBuilder.enableRUM(false).trackUIKitRUMActions().build()
        ) {
            XCTAssertNil(defaultDatadogCore.feature(RUMFeature.self))
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.viewControllerSwizzler)
            XCTAssertNil(defaultDatadogCore.feature(RUMInstrumentation.self)?.userActionsAutoInstrumentation)
        }

        verify(configuration: defaultBuilder.trackURLSession(firstPartyHosts: ["example.com"]).build()) {
            XCTAssertNotNil(URLSessionAutoInstrumentation.instance)
        }
        verify(configuration: defaultBuilder.trackURLSession().build()) {
            XCTAssertNotNil(URLSessionAutoInstrumentation.instance)
        }

        verify(
            configuration: rumBuilder
                .enableLogging(true)
                .enableRUM(false)
                .enableCrashReporting(using: CrashReportingPluginMock())
                .build()
        ) {
            XCTAssertNotNil(CrashReportingFeature.instance)
            XCTAssertTrue(
                Global.crashReporter?.loggingOrRUMIntegration is CrashReportingWithLoggingIntegration,
                "When only Logging feature is enabled, the Crash Reporter should send crash reports as Logs"
            )
        }

        verify(
            configuration: rumBuilder
                .enableLogging(false)
                .enableRUM(true)
                .enableCrashReporting(using: CrashReportingPluginMock())
                .build()
        ) {
            XCTAssertNotNil(CrashReportingFeature.instance)
            XCTAssertTrue(
                Global.crashReporter?.loggingOrRUMIntegration is CrashReportingWithRUMIntegration,
                "When only RUM feature is enabled, the Crash Reporter should send crash reports as RUM Events"
            )
        }

        verify(
            configuration: rumBuilder
                .enableLogging(true)
                .enableRUM(true)
                .enableCrashReporting(using: CrashReportingPluginMock())
                .build()
        ) {
            XCTAssertNotNil(CrashReportingFeature.instance)
            XCTAssertTrue(
                Global.crashReporter?.loggingOrRUMIntegration is CrashReportingWithRUMIntegration,
                "When both Logging and RUM features are enabled, the Crash Reporter should send crash reports as RUM Events"
            )
        }

        verify(
            configuration: rumBuilder
                .enableLogging(false)
                .enableRUM(false)
                .enableCrashReporting(using: CrashReportingPluginMock())
                .build()
        ) {
            XCTAssertNil(CrashReportingFeature.instance)
            XCTAssertNil(
                Global.crashReporter,
                "When both Logging and RUM are disabled, Crash Reporter should not be registered"
            )
        }
    }

    func testSupplyingDebugLaunchArgument_itOverridesUserSettings() {
        let mockProcessInfo = ProcessInfoMock(
            arguments: [Datadog.LaunchArguments.Debug]
        )

        let configuration = rumBuilder
            .set(uploadFrequency: .rare)
            .set(rumSessionsSamplingRate: 20.0)
            .set(batchSize: .medium)
            .build()

        Datadog.initialize(
            appContext: .mockWith(
                processInfo: mockProcessInfo
            ),
            trackingConsent: .pending,
            configuration: configuration
        )

        let expectedPerformancePreset = PerformancePreset(
            batchSize: .small,
            uploadFrequency: .frequent,
            bundleType: .iOSApp
        )

        let core = defaultDatadogCore
        let logging = core.feature(LoggingFeature.self)
        let tracing = core.feature(TracingFeature.self)
        let rum = core.feature(RUMFeature.self)
        XCTAssertEqual(logging?.configuration.common.performance, expectedPerformancePreset)
        XCTAssertEqual(rum?.configuration.sessionSampler.samplingRate, 100)
        XCTAssertEqual(tracing?.configuration.common.performance, expectedPerformancePreset)
        XCTAssertEqual(Datadog.verbosityLevel, .debug)

        // Clear default verbosity after this test
        Datadog.verbosityLevel = nil
        Datadog.flushAndDeinitialize()
    }

    func testSupplyingRumDebugLaunchArgument_itSetsRumDebug() {
        let mockProcessInfo = ProcessInfoMock(
            arguments: [Datadog.LaunchArguments.DebugRUM]
        )

        let configuration = rumBuilder
            .build()

        Datadog.initialize(
            appContext: .mockWith(
                processInfo: mockProcessInfo
            ),
            trackingConsent: .pending,
            configuration: configuration
        )

        XCTAssertTrue(Datadog.debugRUM)

        // Clear debug after test
        Datadog.debugRUM = false
        Datadog.flushAndDeinitialize()
    }

    // MARK: - Public APIs

    func testTrackingConsent() {
        let initialConsent: TrackingConsent = .mockRandom()
        let nextConsent: TrackingConsent = .mockRandom()

        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: initialConsent,
            configuration: defaultBuilder.build()
        )

        let core = defaultDatadogCore as? DatadogCore
        XCTAssertEqual(core?.dependencies.consentProvider.currentValue, initialConsent)

        Datadog.set(trackingConsent: nextConsent)

        XCTAssertEqual(core?.dependencies.consentProvider.currentValue, nextConsent)

        Datadog.flushAndDeinitialize()
    }

    func testUserInfo() {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: defaultBuilder.build()
        )

        let core = defaultDatadogCore as? DatadogCore

        XCTAssertNotNil(core?.dependencies.userInfoProvider.value)
        XCTAssertNil(core?.dependencies.userInfoProvider.value.id)
        XCTAssertNil(core?.dependencies.userInfoProvider.value.email)
        XCTAssertNil(core?.dependencies.userInfoProvider.value.name)
        XCTAssertEqual(core?.dependencies.userInfoProvider.value.extraInfo as? [String: Int], [:])

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        XCTAssertEqual(core?.dependencies.userInfoProvider.value.id, "foo")
        XCTAssertEqual(core?.dependencies.userInfoProvider.value.name, "bar")
        XCTAssertEqual(core?.dependencies.userInfoProvider.value.email, "foo@bar.com")
        XCTAssertEqual(core?.dependencies.userInfoProvider.value.extraInfo as? [String: Int], ["abc": 123])

        Datadog.flushAndDeinitialize()
    }

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }

    func testDefaultDebugRUM() {
        XCTAssertFalse(Datadog.debugRUM)
    }

    func testDeprecatedAPIs() {
        (Datadog.self as DatadogDeprecatedAPIs.Type).initialize(
            appContext: .mockAny(),
            configuration: defaultBuilder.build()
        )

        let core = defaultDatadogCore as? DatadogCore

        XCTAssertEqual(
            core?.dependencies.consentProvider.currentValue,
            .granted,
            "When using deprecated Datadog initialization API the consent should be set to `.granted`"
        )

        Datadog.flushAndDeinitialize()
    }

    func testGivenDataStoredInAllFeatureDirectories_whenClearAllDataIsUsed_allFilesAreRemoved() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: rumBuilder
                .enableLogging(true)
                .enableTracing(true)
                .enableRUM(true)
                .build()
        )

        let core = defaultDatadogCore
        let logging = core.feature(LoggingFeature.self)
        let tracing = core.feature(TracingFeature.self)
        let rum = core.feature(RUMFeature.self)

        // On SDK init, underlying `ConsentAwareDataWriter` performs data migration for each feature, which includes
        // data removal in `unauthorised` (`.pending`) directory. To not cause test flakiness, we must ensure that
        // mock data is written only after this operation completes - otherwise, migration may delete mocked files.
        let loggingWriter = try XCTUnwrap(logging?.storage.writer as? ConsentAwareDataWriter)
        let tracingWriter = try XCTUnwrap(tracing?.storage.writer as? ConsentAwareDataWriter)
        let rumWriter = try XCTUnwrap(rum?.storage.writer as? ConsentAwareDataWriter)
        loggingWriter.queue.sync {}
        tracingWriter.queue.sync {}
        rumWriter.queue.sync {}

        let featureDirectories: [FeatureDirectories] = [
            try obtainLoggingFeatureDirectories(),
            try obtainTracingFeatureDirectories(),
            try obtainRUMFeatureDirectories()
        ]

        let allDirectories: [Directory] = featureDirectories.flatMap { [$0.authorized, $0.unauthorized] }
        try allDirectories.forEach { directory in _ = try directory.createFile(named: .mockRandom()) }

        // Given
        let numberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(numberOfFiles, 6, "Each feature stores 2 files - one authorised and one unauthorised")

        // When
        Datadog.clearAllData()

        // Wait for async clear completion in all features:
        (logging?.storage.dataOrchestrator as? DataOrchestrator)?.queue.sync {}
        (tracing?.storage.dataOrchestrator as? DataOrchestrator)?.queue.sync {}
        (rum?.storage.dataOrchestrator as? DataOrchestrator)?.queue.sync {}

        // Then
        let newNumberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(newNumberOfFiles, 0, "All files must be removed")

        Datadog.flushAndDeinitialize()
    }
}

class AppContextTests: XCTestCase {
    func testBundleType() {
        let iOSAppBundle: Bundle = .mockWith(bundlePath: "mock.app")
        let iOSAppExtensionBundle: Bundle = .mockWith(bundlePath: "mock.appex")
        XCTAssertEqual(AppContext(mainBundle: iOSAppBundle).bundleType, .iOSApp)
        XCTAssertEqual(AppContext(mainBundle: iOSAppExtensionBundle).bundleType, .iOSAppExtension)
    }

    func testBundleIdentifier() {
        XCTAssertEqual(AppContext(mainBundle: .mockWith(bundleIdentifier: "com.abc.app")).bundleIdentifier, "com.abc.app")
        XCTAssertNil(AppContext(mainBundle: .mockWith(bundleIdentifier: nil)).bundleIdentifier)
    }

    func testBundleVersion() {
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

    func testBundleName() {
        XCTAssertEqual(
            AppContext(mainBundle: .mockWith(bundlePath: .mockAny(), CFBundleExecutable: "FooApp")).bundleName,
            "FooApp"
        )
    }
}

// MARK: - Deprecation Helpers

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol DatadogDeprecatedAPIs {
    static func initialize(appContext: AppContext, configuration: Datadog.Configuration)
}
extension Datadog: DatadogDeprecatedAPIs {}
