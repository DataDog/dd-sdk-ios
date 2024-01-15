/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogLogs
@testable import DatadogTrace
@testable import DatadogCore

class DatadogTests: XCTestCase {
    private var printFunction: PrintFunctionMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var defaultConfig = Datadog.Configuration(clientToken: "abc-123", env: "tests")

    override func setUp() {
        super.setUp()

        XCTAssertFalse(Datadog.isInitialized())
        printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { print($0) }
        printFunction = nil
        XCTAssertFalse(Datadog.isInitialized())
        super.tearDown()
    }

    // MARK: - Initializing with different configurations

    func testDefaultConfiguration() throws {
        var configuration = defaultConfig

        configuration.bundle = .mockWith(
            bundleIdentifier: "test",
            CFBundleShortVersionString: "1.0.0",
            CFBundleExecutable: "Test"
        )

        XCTAssertEqual(configuration.batchSize, .medium)
        XCTAssertEqual(configuration.uploadFrequency, .average)
        XCTAssertEqual(configuration.additionalConfiguration.count, 0)
        XCTAssertNil(configuration.encryption)
        XCTAssertTrue(configuration.serverDateProvider is DatadogNTPDateProvider)

        Datadog.initialize(
            with: configuration,
            trackingConsent: .granted
        )
        defer { Datadog.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)
        let urlSessionClient = try XCTUnwrap(core.httpClient as? URLSessionClient)
        XCTAssertTrue(core.dateProvider is SystemDateProvider)
        XCTAssertNil(urlSessionClient.session.configuration.connectionProxyDictionary)
        XCTAssertNil(core.encryption)

        let context = core.contextProvider.read()
        XCTAssertEqual(context.clientToken, "abc-123")
        XCTAssertEqual(context.env, "tests")
        XCTAssertEqual(context.site, .us1)
        XCTAssertEqual(context.service, "test")
        XCTAssertEqual(context.version, "1.0.0")
        XCTAssertEqual(context.sdkVersion, __sdkVersion)
        XCTAssertEqual(context.applicationName, "Test")
        XCTAssertNil(context.variant)
        XCTAssertEqual(context.source, "ios")
        XCTAssertEqual(context.applicationBundleIdentifier, "test")
        XCTAssertEqual(context.trackingConsent, .granted)
    }

    func testAdvancedConfiguration() throws {
        var configuration = defaultConfig

        configuration.service = "service-name"
        configuration.site = .eu1
        configuration.batchSize = .small
        configuration.uploadFrequency = .frequent
        configuration.proxyConfiguration = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPPort: 123,
            kCFNetworkProxiesHTTPProxy: "www.example.com",
            kCFProxyUsernameKey: "proxyuser",
            kCFProxyPasswordKey: "proxypass",
        ]
        configuration.bundle = .mockWith(
            bundleIdentifier: "test",
            CFBundleShortVersionString: "1.0.0",
            CFBundleExecutable: "Test"
        )
        configuration.encryption = DataEncryptionMock()
        configuration.serverDateProvider = ServerDateProviderMock()
        configuration._internal_mutation {
            $0.additionalConfiguration = [
                CrossPlatformAttributes.ddsource: "cp-source",
                CrossPlatformAttributes.variant: "cp-variant",
                CrossPlatformAttributes.sdkVersion: "cp-version"
            ]
        }

        XCTAssertEqual(configuration.batchSize, .small)
        XCTAssertEqual(configuration.uploadFrequency, .frequent)
        XCTAssertTrue(configuration.encryption is DataEncryptionMock)
        XCTAssertTrue(configuration.serverDateProvider is ServerDateProviderMock)

        Datadog.initialize(
            with: configuration,
            trackingConsent: .pending
        )
        defer { Datadog.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)
        XCTAssertTrue(core.dateProvider is SystemDateProvider)
        XCTAssertTrue(core.encryption is DataEncryptionMock)

        let urlSessionClient = try XCTUnwrap(core.httpClient as? URLSessionClient)
        let connectionProxyDictionary = try XCTUnwrap(urlSessionClient.session.configuration.connectionProxyDictionary)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(connectionProxyDictionary[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(connectionProxyDictionary[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(connectionProxyDictionary[kCFProxyPasswordKey] as? String, "proxypass")

        let context = core.contextProvider.read()
        XCTAssertEqual(context.clientToken, "abc-123")
        XCTAssertEqual(context.env, "tests")
        XCTAssertEqual(context.site, .eu1)
        XCTAssertEqual(context.service, "service-name")
        XCTAssertEqual(context.version, "1.0.0")
        XCTAssertEqual(context.sdkVersion, "cp-version")
        XCTAssertEqual(context.applicationName, "Test")
        XCTAssertEqual(context.variant, "cp-variant")
        XCTAssertEqual(context.source, "cp-source")
        XCTAssertEqual(context.applicationBundleIdentifier, "test")
        XCTAssertEqual(context.trackingConsent, .pending)
    }

    func testGivenDefaultConfiguration_itCanBeInitialized() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )
        XCTAssertTrue(Datadog.isInitialized())
        Datadog.flushAndDeinitialize()
    }

    func testGivenInvalidConfiguration_itPrintsError() {
        let invalidConfiguration = Datadog.Configuration(clientToken: "", env: "tests")

        Datadog.initialize(
            with: invalidConfiguration,
            trackingConsent: .mockRandom()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `clientToken` cannot be empty."
        )
        XCTAssertFalse(Datadog.isInitialized())
    }

    func testGivenValidConfiguration_whenInitializedMoreThanOnce_itPrintsError() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: The 'main' instance of SDK is already initialized."
        )

        Datadog.flushAndDeinitialize()
    }

    // MARK: - Public APIs

    func testTrackingConsent() {
        let initialConsent: TrackingConsent = .mockRandom()
        let nextConsent: TrackingConsent = .mockRandom()

        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: initialConsent
        )

        let core = CoreRegistry.default as? DatadogCore
        XCTAssertEqual(core?.consentPublisher.consent, initialConsent)

        Datadog.set(trackingConsent: nextConsent)

        XCTAssertEqual(core?.consentPublisher.consent, nextConsent)

        Datadog.flushAndDeinitialize()
    }

    func testUserInfo() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        XCTAssertNil(core?.userInfoPublisher.current.id)
        XCTAssertNil(core?.userInfoPublisher.current.email)
        XCTAssertNil(core?.userInfoPublisher.current.name)
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], [:])

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["abc": 123])

        Datadog.flushAndDeinitialize()
    }

    func testAddUserPreoprties_mergesProperties() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        Datadog.addUserExtraInfo(["second": 667])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(
            core?.userInfoPublisher.current.extraInfo as? [String: Int],
            ["abc": 123, "second": 667]
        )

        Datadog.flushAndDeinitialize()
    }

    func testAddUserPreoprties_removesProperties() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        Datadog.addUserExtraInfo(["abc": nil, "second": 667])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["second": 667])

        Datadog.flushAndDeinitialize()
    }

    func testAddUserPreoprties_overwritesProperties() {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )

        Datadog.addUserExtraInfo(["abc": 444])

        XCTAssertEqual(core?.userInfoPublisher.current.id, "foo")
        XCTAssertEqual(core?.userInfoPublisher.current.name, "bar")
        XCTAssertEqual(core?.userInfoPublisher.current.email, "foo@bar.com")
        XCTAssertEqual(core?.userInfoPublisher.current.extraInfo as? [String: Int], ["abc": 444])

        Datadog.flushAndDeinitialize()
    }

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }

    func testGivenDataStoredInAllFeatureDirectories_whenClearAllDataIsUsed_allFilesAreRemoved() throws {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        Logs.enable()
        Trace.enable()

        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)

        // On SDK init, underlying `ConsentAwareDataWriter` performs data migration for each feature, which includes
        // data removal in `unauthorised` (`.pending`) directory. To not cause test flakiness, we must ensure that
        // mock data is written only after this operation completes - otherwise, migration may delete mocked files.
        core.readWriteQueue.sync {}

        let featureDirectories: [FeatureDirectories] = [
            try core.directory.getFeatureDirectories(forFeatureNamed: "logging"),
            try core.directory.getFeatureDirectories(forFeatureNamed: "tracing"),
        ]

        let allDirectories: [Directory] = featureDirectories.flatMap { [$0.authorized, $0.unauthorized] }
        try allDirectories.forEach { directory in _ = try directory.createFile(named: .mockRandom()) }

        // Given
        let numberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(numberOfFiles, 4, "Each feature stores 2 files - one authorised and one unauthorised")

        // When
        Datadog.clearAllData()

        // Wait for async clear completion in all features:
        core.readWriteQueue.sync {}

        // Then
        let newNumberOfFiles = try allDirectories.reduce(0, { acc, nextDirectory in return try acc + nextDirectory.files().count })
        XCTAssertEqual(newNumberOfFiles, 0, "All files must be removed")

        Datadog.flushAndDeinitialize()
    }

    func testServerDateProvider() throws {
        // Given
        var config = defaultConfig
        let serverDateProvider = ServerDateProviderMock()
        config.serverDateProvider = serverDateProvider

        // When
        Datadog.initialize(
            with: config,
            trackingConsent: .mockRandom()
        )

        serverDateProvider.offset = -1

        // Then
        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)
        let context = core.contextProvider.read()
        XCTAssertEqual(context.serverTimeOffset, -1)

        Datadog.flushAndDeinitialize()
    }

    func testRemoveV1DeprecatedFolders() throws {
        // Given
        let cache = try Directory.cache()
        let directories = ["com.datadoghq.logs", "com.datadoghq.traces", "com.datadoghq.rum"]
        try directories.forEach {
            _ = try cache.createSubdirectory(path: $0).createFile(named: "test")
        }

        // When
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        defer { Datadog.flushAndDeinitialize() }

        let core = try XCTUnwrap(CoreRegistry.default as? DatadogCore)
        // Wait for async deletion
        core.readWriteQueue.sync {}

        // Then
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.logs"))
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.traces"))
        XCTAssertThrowsError(try cache.subdirectory(path: "com.datadoghq.rum"))
    }

    func testCustomSDKInstance() throws {
        // When
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom(),
            instanceName: "test"
        )

        defer { Datadog.flushAndDeinitialize(instanceName: "test") }

        // Then
        XCTAssertTrue(CoreRegistry.default is NOPDatadogCore)
        XCTAssertTrue(CoreRegistry.instance(named: "test") is DatadogCore)
    }

    func testStopSDKInstance() throws {
        // Given
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom(),
            instanceName: "test"
        )

        // Then
        XCTAssertTrue(CoreRegistry.instance(named: "test") is DatadogCore)

        // When
        Datadog.stopInstance(named: "test")

        // Then
        XCTAssertTrue(CoreRegistry.instance(named: "test") is NOPDatadogCore)
    }

    func testGivenDefaultSDKInstanceInitialized_customOneCanBeInitializedAfterIt() throws {
        let defaultConfig = Datadog.Configuration(clientToken: "abc-123", env: "default")
        let customConfig = Datadog.Configuration(clientToken: "def-456", env: "custom")

        // Given
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )
        defer { Datadog.flushAndDeinitialize() }

        // When
        Datadog.initialize(
            with: customConfig,
            trackingConsent: .mockRandom(),
            instanceName: "custom-instance"
        )
        defer { Datadog.flushAndDeinitialize(instanceName: "custom-instance") }

        // Then
        XCTAssertTrue(CoreRegistry.default is DatadogCore)
        XCTAssertTrue(CoreRegistry.instance(named: "custom-instance") is DatadogCore)
    }
}
