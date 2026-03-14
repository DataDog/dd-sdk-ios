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
    private var printFunction: PrintFunctionSpy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var defaultConfig = Datadog.Configuration(clientToken: "abc-123", env: "tests")

    override func setUp() {
        super.setUp()

        XCTAssertFalse(Datadog.isInitialized())
        printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
    }

    override func tearDown() {
        consolePrint = { message, _ in print(message) }
        printFunction = nil
        XCTAssertFalse(Datadog.isInitialized())
        super.tearDown()
    }

    // MARK: - Initializing with different configurations

    func testDefaultConfiguration() async throws {
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

        let context = await core.contextProvider.read()
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

    func testAdvancedConfiguration() async throws {
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

        let context = await core.contextProvider.read()
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

    func testTrackingConsent() async {
        let initialConsent: TrackingConsent = .mockRandom()
        let nextConsent: TrackingConsent = .mockRandom()

        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: initialConsent
        )

        let core = CoreRegistry.default as? DatadogCore
        let initialContext = await core?.contextProvider.read()
        XCTAssertEqual(initialContext?.trackingConsent, initialConsent)

        Datadog.set(trackingConsent: nextConsent)

        let updatedContext = await core?.contextProvider.read()
        XCTAssertEqual(updatedContext?.trackingConsent, nextConsent)

        Datadog.flushAndDeinitialize()
    }

    func testUserInfo() async {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        var context = await core?.contextProvider.read()
        var userInfo = context?.userInfo
        XCTAssertNil(userInfo?.id)
        XCTAssertNil(userInfo?.email)
        XCTAssertNil(userInfo?.name)
        XCTAssertEqual(userInfo?.extraInfo as? [String: Int], [:])

        Datadog.setUserInfo(
            id: "foo",
            name: "bar",
            email: "foo@bar.com",
            extraInfo: ["abc": 123]
        )
        core?.set(anonymousId: "anonymous-id")

        context = await core?.contextProvider.read()
        userInfo = context?.userInfo
        XCTAssertEqual(userInfo?.anonymousId, "anonymous-id")
        XCTAssertEqual(userInfo?.id, "foo")
        XCTAssertEqual(userInfo?.name, "bar")
        XCTAssertEqual(userInfo?.email, "foo@bar.com")
        XCTAssertEqual(userInfo?.extraInfo as? [String: Int], ["abc": 123])

        Datadog.clearUserInfo()

        context = await core?.contextProvider.read()
        userInfo = context?.userInfo
        XCTAssertEqual(userInfo?.anonymousId, "anonymous-id")
        XCTAssertNil(userInfo?.id)
        XCTAssertNil(userInfo?.email)
        XCTAssertNil(userInfo?.name)
        XCTAssertEqual(userInfo?.extraInfo as? [String: Int], [:])

        Datadog.flushAndDeinitialize()
    }

    func testAddUserProperties_mergesProperties() async {
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

        let context = await core?.contextProvider.read()
        let userInfo = context?.userInfo
        XCTAssertEqual(userInfo?.id, "foo")
        XCTAssertEqual(userInfo?.name, "bar")
        XCTAssertEqual(userInfo?.email, "foo@bar.com")
        XCTAssertEqual(
            userInfo?.extraInfo as? [String: Int],
            ["abc": 123, "second": 667]
        )

        Datadog.flushAndDeinitialize()
    }

    func testAddUserProperties_removesProperties() async {
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

        let context = await core?.contextProvider.read()
        let userInfo = context?.userInfo
        XCTAssertEqual(userInfo?.id, "foo")
        XCTAssertEqual(userInfo?.name, "bar")
        XCTAssertEqual(userInfo?.email, "foo@bar.com")
        XCTAssertEqual(userInfo?.extraInfo as? [String: Int], ["second": 667])

        Datadog.flushAndDeinitialize()
    }

    func testAddUserProperties_overwritesProperties() async {
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

        let context = await core?.contextProvider.read()
        let userInfo = context?.userInfo
        XCTAssertEqual(userInfo?.id, "foo")
        XCTAssertEqual(userInfo?.name, "bar")
        XCTAssertEqual(userInfo?.email, "foo@bar.com")
        XCTAssertEqual(userInfo?.extraInfo as? [String: Int], ["abc": 444])

        Datadog.flushAndDeinitialize()
    }

    func testAccountInfo() async {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        var context = await core?.contextProvider.read()
        XCTAssertNil(context?.accountInfo)

        Datadog.setAccountInfo(
            id: "foo",
            name: "bar",
            extraInfo: ["abc": 123]
        )

        context = await core?.contextProvider.read()
        XCTAssertEqual(context?.accountInfo?.id, "foo")
        XCTAssertEqual(context?.accountInfo?.name, "bar")
        XCTAssertEqual(context?.accountInfo?.extraInfo as? [String: Int], ["abc": 123])

        Datadog.flushAndDeinitialize()
    }

    func testAddAccountProperties_mergesProperties() async {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setAccountInfo(
            id: "foo",
            name: "bar",
            extraInfo: ["abc": 123]
        )

        Datadog.addAccountExtraInfo(["second": 667])

        let context = await core?.contextProvider.read()
        XCTAssertEqual(context?.accountInfo?.id, "foo")
        XCTAssertEqual(context?.accountInfo?.name, "bar")
        XCTAssertEqual(
            context?.accountInfo?.extraInfo as? [String: Int],
            ["abc": 123, "second": 667]
        )

        Datadog.flushAndDeinitialize()
    }

    func testAddAccountProperties_removesProperties() async {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setAccountInfo(
            id: "foo",
            name: "bar",
            extraInfo: ["abc": 123]
        )

        Datadog.addAccountExtraInfo(["abc": nil, "second": 667])

        let context = await core?.contextProvider.read()
        XCTAssertEqual(context?.accountInfo?.id, "foo")
        XCTAssertEqual(context?.accountInfo?.name, "bar")
        XCTAssertEqual(context?.accountInfo?.extraInfo as? [String: Int], ["second": 667])

        Datadog.flushAndDeinitialize()
    }

    func testAddAccountProperties_overwritesProperties() async {
        Datadog.initialize(
            with: defaultConfig,
            trackingConsent: .mockRandom()
        )

        let core = CoreRegistry.default as? DatadogCore

        Datadog.setAccountInfo(
            id: "foo",
            name: "bar",
            extraInfo: ["abc": 123]
        )

        Datadog.addAccountExtraInfo(["abc": 444])

        let context = await core?.contextProvider.read()
        XCTAssertEqual(context?.accountInfo?.id, "foo")
        XCTAssertEqual(context?.accountInfo?.name, "bar")
        XCTAssertEqual(context?.accountInfo?.extraInfo as? [String: Int], ["abc": 444])

        Datadog.flushAndDeinitialize()
    }

    func testDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
    }

    @MainActor
    func testGivenDataStoredInAllFeatureDirectories_whenClearAllDataIsUsed_allFilesAreRemoved() async throws {
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
        await core.flush()

        // Given
        let featureDirectories: [FeatureDirectories] = [
            try core.directory.getFeatureDirectories(forFeatureNamed: "logging"),
            try core.directory.getFeatureDirectories(forFeatureNamed: "tracing"),
        ]

        let scope = core.scope(for: TraceFeature.self)
        scope.dataStore.setValue("foo".data(using: .utf8)!, forKey: "bar")

        await core.flush()
        let tracingDataStoreDir = try core.directory.coreDirectory.subdirectory(path: core.directory.getDataStorePath(forFeatureNamed: "tracing"))
        XCTAssertTrue(tracingDataStoreDir.hasFile(named: "bar"))

        var allDirectories: [Directory] = featureDirectories.flatMap { [$0.authorized, $0.unauthorized] }
        allDirectories.append(.init(url: tracingDataStoreDir.url))
        try allDirectories.forEach { directory in _ = try directory.createFile(named: .mockRandom()) }

        // When
        Datadog.clearAllData()

        await core.flush()

        // Then
        let files: [File] = allDirectories.reduce([], { acc, nextDirectory in
            let next = try? nextDirectory.files()
            return acc + (next ?? [])
        })
        XCTAssertEqual(files, [], "All files must be removed")

        Datadog.flushAndDeinitialize()
    }

    func testServerDateProvider() async throws {
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
        let context = await core.contextProvider.read()
        XCTAssertEqual(context.serverTimeOffset, -1)

        Datadog.flushAndDeinitialize()
    }

    func testRemoveV1DeprecatedFolders() async throws {
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

        // Wait for async Task.detached deletion to complete
        try await Task.sleep(nanoseconds: 500_000_000)

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
