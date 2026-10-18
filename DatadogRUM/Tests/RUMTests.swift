/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import UIKit
#endif
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Experimental)
@testable import DatadogRUM

class RUMTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        config = RUM.Configuration(applicationID: .mockAny())
    }

    override func tearDown() {
        core = nil
        config = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
        XCTAssertEqual(PassthroughCoreMock.referenceCount, 0)
    }

    func testWhenNotEnabled_thenRUMMonitorIsNotAvailable() {
        // When
        XCTAssertNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is NOPMonitor)
    }

    func testWhenNotEnabled_thenRumIsEnabledIsFalse() {
        // When
        XCTAssertNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertFalse(RUM._internal.isEnabled(in: core))
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        RUM.enable(with: config, in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `RUM.enable(with:)`."
        )
    }

    func testWhenEnabled_thenRUMMonitorIsAvailable() {
        // When
        RUM.enable(with: config, in: core)
        XCTAssertNotNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
    }

    func testWhenEnabled_thenRumIsEnabledIsTrue() {
        // When
        RUM.enable(with: config, in: core)
        XCTAssertNotNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUM._internal.isEnabled(in: core))
    }

    // MARK: - Configuration Tests

    func testWhenEnabled_thenSessionSamplerIsAvailableBeforeEnableReturns() throws {
        // Given
        // This session ID is not sampled at 50%, but it is sampled at 60%:
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        config.sessionSampleRate = 60
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))

        // When
        RUM.enable(with: config, in: core)

        // Then - deliberately no `flush()` and no waiting: the sampling decision must already be resolved
        // by the time `RUM.enable()` returns, otherwise Features instrumenting a request right here (e.g.
        // WebViewTracking) get no decision at all. See RUM-17921.
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let snapshot = try XCTUnwrap(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            "The session sampling decision must be available synchronously, without waiting for the initial session"
        )
        XCTAssertEqual(snapshot.sessionID, RUMUUID(rawValue: sessionUUID).toRUMDataFormat)
        XCTAssertEqual(snapshot.isSampled, DeterministicSampler(uuid: sessionUUID, samplingRate: 60).isSampled)
        XCTAssertTrue(snapshot.isSampled)
    }

    func testWhenEnabledWithDebugSDK_thenSessionSamplerUsesTheOverriddenRate() throws {
        // Given
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        config.sessionSampleRate = 0
        config.debugSDK = true
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))

        // When
        RUM.enable(with: config, in: core)

        // Then - `debugSDK` forces 100%, and the synchronous store must honour it like the session does
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let snapshot = try XCTUnwrap(rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate))
        XCTAssertEqual(snapshot.sessionID, RUMUUID(rawValue: sessionUUID).toRUMDataFormat)
        XCTAssertTrue(snapshot.isSampled, "A 0% configured rate must still be forced to 100% by `debugSDK`")
    }

    func testMultiSceneTrackingResolutionRequiresFlagManifestAndSupportedOS() {
        let manifests: [(Any?, Bool)] = [
            (nil, false),
            ("invalid", false),
            ([:], false),
            (["UIApplicationSupportsMultipleScenes": false], false),
            (["UIApplicationSupportsMultipleScenes": "true"], false),
            (["UIApplicationSupportsMultipleScenes": 1], false),
            (["UIApplicationSupportsMultipleScenes": NSNumber(value: 1)], false),
            (["UIApplicationSupportsMultipleScenes": true], true),
            (["UIApplicationSupportsMultipleScenes": NSNumber(value: true)], true),
            (["UIApplicationSceneConfigurations": ["UIApplicationSupportsMultipleScenes": true]], false)
        ]
        let requests: [Bool?] = [nil, false, true]

        for (manifest, isMultiSceneManifest) in manifests {
            for request in requests {
                for isSupportedOS in [false, true] {
                    var flags: RUM.Configuration.FeatureFlags = [.viewUpdates: false]
                    flags[.multiSceneTracking] = request
                    let resolved = RUMFeature.resolvedFeatureFlags(
                        flags,
                        bundle: .mockWith(UIApplicationSceneManifest: manifest),
                        supportsMultiSceneTracking: isSupportedOS
                    )
                    XCTAssertEqual(
                        resolved[.multiSceneTracking],
                        request == true && isSupportedOS && isMultiSceneManifest,
                        "request=\(String(describing: request)), manifest=\(String(describing: manifest)), supported=\(isSupportedOS)"
                    )
                    XCTAssertFalse(resolved[.viewUpdates])
                    XCTAssertTrue(resolved[.trackScrollAndSwipeActions])
                    var otherFlags = resolved
                    otherFlags.removeValue(forKey: .multiSceneTracking)
                    var requestedOtherFlags = flags
                    requestedOtherFlags.removeValue(forKey: .multiSceneTracking)
                    XCTAssertEqual(otherFlags, requestedOtherFlags)
                }
            }
        }
    }

    func testDisabledMultiSceneTrackingDoesNotReadTheSceneManifest() {
        let bundle = MutableSceneManifestBundle()
        bundle.sceneManifest = ["UIApplicationSupportsMultipleScenes": true]

        for flags: RUM.Configuration.FeatureFlags in [[:], [.multiSceneTracking: false]] {
            let resolved = RUMFeature.resolvedFeatureFlags(flags, bundle: bundle, supportsMultiSceneTracking: true)
            XCTAssertFalse(resolved[.multiSceneTracking])
        }
        _ = RUMFeature.resolvedFeatureFlags([.multiSceneTracking: true], bundle: bundle, supportsMultiSceneTracking: false)
        XCTAssertEqual(bundle.sceneManifestReads, 0)
    }

    func testMultiSceneTrackingIsFrozenInFeatureAndScopeDependencies() throws {
        let bundle = MutableSceneManifestBundle()
        bundle.sceneManifest = ["UIApplicationSupportsMultipleScenes": true]
        config.bundle = bundle
        config.featureFlags = [.multiSceneTracking: true, .viewUpdates: false]

        RUM.enable(with: config, in: core)

        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(rum.monitor as? Monitor)
        let expectedMode: Bool
        #if os(iOS)
        if #available(iOS 27.0, *) {
            expectedMode = true
        } else {
            expectedMode = false
        }
        #else
        expectedMode = false
        #endif
        let readsAfterEnable = bundle.sceneManifestReads
        bundle.sceneManifest = ["UIApplicationSupportsMultipleScenes": false]
        config.featureFlags = [.multiSceneTracking: false, .viewUpdates: true]

        XCTAssertEqual(rum.isMultiSceneTrackingEnabled, expectedMode)
        XCTAssertEqual(monitor.applicationScope.dependencies.isMultiSceneTrackingEnabled, expectedMode)
        XCTAssertEqual(monitor.applicationScope.dependencies.featureFlags[.multiSceneTracking], expectedMode)
        XCTAssertFalse(monitor.applicationScope.dependencies.featureFlags[.viewUpdates])
        XCTAssertTrue(monitor.applicationScope.dependencies.featureFlags[.trackScrollAndSwipeActions])
        XCTAssertTrue(rum.configuration.featureFlags[.multiSceneTracking], "The requested configuration remains unchanged")
        XCTAssertEqual(bundle.sceneManifestReads, readsAfterEnable, "Reading frozen mode must not re-read the manifest")
    }

    func testMultiSceneTrackingWithoutManifestResolvesOffInScopeDependencies() throws {
        config.bundle = .mockWith()
        config.featureFlags = [.multiSceneTracking: true]

        RUM.enable(with: config, in: core)

        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(rum.monitor as? Monitor)
        XCTAssertFalse(rum.isMultiSceneTrackingEnabled)
        XCTAssertFalse(monitor.applicationScope.dependencies.isMultiSceneTrackingEnabled)
        XCTAssertFalse(monitor.applicationScope.dependencies.featureFlags[.multiSceneTracking])
        XCTAssertTrue(rum.configuration.featureFlags[.multiSceneTracking])
        XCTAssertTrue(monitor.applicationScope.dependencies.featureFlags[.viewUpdates])
        XCTAssertTrue(monitor.applicationScope.dependencies.featureFlags[.trackScrollAndSwipeActions])
    }

    @MainActor
    func testResolvedOnActivatesBeforeFeatureScopeAndInstrumentationInitialization() throws {
        let activationCore = HandoffActivationCoreMock()
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: config, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        if rum.isMultiSceneTrackingEnabled {
            XCTAssertEqual(activationCore.activations, 1)
            XCTAssertTrue(activationCore.rumScopeObservedActiveOwner)
            XCTAssertTrue(rum.rumContextHandoffOwner === activationCore.issuedOwners.first)
            XCTAssertEqual(activationCore.ownerBoundRegistrations, 1)
        } else {
            XCTAssertEqual(activationCore.activations, 0)
            XCTAssertNil(rum.rumContextHandoffOwner)
            XCTAssertEqual(activationCore.ownerBoundRegistrations, 0)
        }
    }

    @MainActor
    func testInitializationFailureRollsBackOnlyIssuedHandoff() throws {
        let activationCore = HandoffActivationCoreMock()
        activationCore.rejectedFeatureName = HeatmapIdentifierRegistryFeature.name
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        XCTAssertThrowsError(try RUM.enableOrThrow(with: config, in: activationCore))
        XCTAssertNil(activationCore.rumContextHandoffOwner)
        XCTAssertTrue(activationCore.issuedOwners.allSatisfy { !$0.isValid })
        XCTAssertEqual(activationCore.rollbacks, activationCore.activations)
        XCTAssertNil(activationCore.get(feature: RUMFeature.self))
    }

    @MainActor
    func testRegistrationFailureRollsBackOnlyIssuedHandoff() throws {
        let activationCore = HandoffActivationCoreMock()
        activationCore.rejectedFeatureName = RUMFeature.name
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        XCTAssertThrowsError(try RUM.enableOrThrow(with: config, in: activationCore))
        XCTAssertNil(activationCore.rumContextHandoffOwner)
        XCTAssertTrue(activationCore.issuedOwners.allSatisfy { !$0.isValid })
        XCTAssertEqual(activationCore.rollbacks, activationCore.activations)
        XCTAssertNil(activationCore.get(feature: RUMFeature.self))
    }

    @MainActor
    func testDefaultAndExplicitOffNeverCallActivationOrOwnerBoundRegistration() throws {
        for flags: RUM.Configuration.FeatureFlags in [[:], [.multiSceneTracking: false]] {
            let activationCore = HandoffActivationCoreMock()
            config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
            config.featureFlags = flags
            try RUM.enableOrThrow(with: config, in: activationCore)
            XCTAssertEqual(activationCore.activations, 0)
            XCTAssertEqual(activationCore.rollbacks, 0)
            XCTAssertEqual(activationCore.ownerBoundRegistrations, 0)
            XCTAssertEqual(activationCore.ownerReads, 0)
            XCTAssertNil(try XCTUnwrap(activationCore.get(feature: RUMFeature.self)).rumContextHandoffOwner)
        }
    }

    func testWhenEnabledWithDefaultConfiguration() throws {
        // Given
        let applicationID: String = .mockRandom()
        config = RUM.Configuration(applicationID: applicationID)

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        let crashReportReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(rum.performanceOverride?.maxFileAgeForRead, 24.hours)
        XCTAssertEqual(monitor.applicationScope.dependencies.rumApplicationID, applicationID)
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, 100)
        XCTAssertEqual(monitor.applicationScope.dependencies.sessionEndedMetric.sampleRate, 15)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 20)
        XCTAssertEqual(crashReportReceiver?.sessionSampler.samplingRate, 100)
    }

    #if !os(watchOS)
    func testWhenEnabledWithAllInstrumentations() throws {
        // Given
        #if os(macOS)
        config.appKitViewsPredicate = UIKitRUMViewsPredicateMock()
        config.macOSActionsPredicate = MacOSRUMActionsPredicateMock()
        #else
        config.uiKitViewsPredicate = UIKitRUMViewsPredicateMock()
        config.uiKitActionsPredicate = UIKitRUMActionsPredicateMock()
        #endif
        config.swiftUIViewsPredicate = SwiftUIRUMViewsPredicateMock()
        #if !os(macOS)
        config.swiftUIActionsPredicate = SwiftUIRUMActionsPredicateMock()
        #endif
        config.longTaskThreshold = 0.5
        config.appHangThreshold = 2

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(monitor, rum.instrumentation.viewsHandler.subscriber)
        XCTAssertIdentical(monitor, (rum.instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber)
        XCTAssertIdentical(monitor, rum.instrumentation.longTasks?.subscriber)
        XCTAssertIdentical(monitor, rum.instrumentation.appHangs?.nonFatalHangsHandler.subscriber)
        #if !os(macOS)
        XCTAssertIdentical(monitor, (rum.instrumentation.memoryWarningMonitor?.reporter as? MemoryWarningReporter)?.subscriber)
        #endif
    }

    #if !os(tvOS) && !os(macOS)
    func testWhenEnabledWithEmptyFeatureFlags_scrollAndSwipeTrackingRemainsEnabled() throws {
        // Given
        config.uiKitActionsPredicate = UIKitRUMActionsPredicateMock()
        config.featureFlags = [:]

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        DDAssertActiveSwizzlings(["sendEvent:", "setDelegate:", "delegate"])
        XCTAssertNotNil(rum.instrumentation.scrollViewSwizzler)
        XCTAssertNotNil(rum.instrumentation.scrollHandler)
    }
    #endif

    func testWhenEnabledWithNoInstrumentations() throws {
        // Given
        #if os(macOS)
        config.appKitViewsPredicate = nil
        config.macOSActionsPredicate = nil
        #else
        config.uiKitViewsPredicate = nil
        config.uiKitActionsPredicate = nil
        #endif
        config.swiftUIViewsPredicate = nil
        #if !os(macOS)
        config.swiftUIActionsPredicate = nil
        #endif
        config.longTaskThreshold = nil
        config.appHangThreshold = nil
        config.trackMemoryWarnings = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(
            monitor,
            rum.instrumentation.viewsHandler.subscriber,
            "It must always subscribe RUM monitor to `RUMViewsHandler` as it is required for SwiftUI instrumentation"
        )
        XCTAssertIdentical(
            monitor,
            (rum.instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber,
            "It must always subscribe RUM monitor to `RUMActionsHandler` as it is required for SwiftUI instrumentation"
        )
        XCTAssertNil(rum.instrumentation.longTasks)
        XCTAssertNil(rum.instrumentation.appHangs)
        XCTAssertNil(rum.instrumentation.memoryWarningMonitor)
    }
    #endif

    func testWhenEnabledWithInvalidLongTasksThreshold() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        config.longTaskThreshold = -5

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertEqual(dd.logger.errorLog?.message, "`RUM.Configuration.longTaskThreshold` cannot be less than 0s. Long Tasks monitoring will be disabled.")
    }

    func testWhenEnabledWithInvalidAppHangThreshold() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        config.appHangThreshold = .mockRandom(min: -10, max: 0.0999)

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertEqual(dd.logger.warnLog?.message, "`RUM.Configuration.appHangThreshold` cannot be less than 0.1s. A value of 0.1s will be used.")
    }

    func testWhenEnabledWithURLSessionTracking() throws {
        // Given
        config.urlSessionTracking = .init()

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should enable `NetworkInstrumentationFeature`"
        )
        let rumResourcesHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: URLSessionRUMResourcesHandler.self),
            "It should register `URLSessionRUMResourcesHandler` to `NetworkInstrumentationFeature`"
        )
        XCTAssertIdentical(
            monitor,
            rumResourcesHandler.subscriber,
            "It must subscribe `RUMMonitor` to `URLSessionRUMResourcesHandler`"
        )
    }

    func testWhenEnabledWithNoURLSessionTracking() {
        // Given
        config.urlSessionTracking = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
        XCTAssertNil(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should not enable `NetworkInstrumentationFeature`"
        )
    }

    func testWhenEnabledWithVitalsUpdateFrequency() throws {
        // Given
        config.vitalsUpdateFrequency = [.frequent, .average, .rare].randomElement()!

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNotNil(monitor.applicationScope.dependencies.vitalsReaders)
    }

    func testWhenEnabledWithNoVitalsUpdateFrequency() throws {
        // Given
        config.vitalsUpdateFrequency = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNil(monitor.applicationScope.dependencies.vitalsReaders)
    }

    func testWhenEnabledWithEventMappers() throws {
        // Given
        config.viewEventMapper = { $0 }
        config.resourceEventMapper = { $0 }
        config.actionEventMapper = { $0 }
        config.errorEventMapper = { $0 }
        config.longTaskEventMapper = { $0 }

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let eventsMapper = monitor.applicationScope.dependencies.eventBuilder.eventsMapper
        XCTAssertNotNil(eventsMapper.viewEventMapper)
        XCTAssertNotNil(eventsMapper.resourceEventMapper)
        XCTAssertNotNil(eventsMapper.actionEventMapper)
        XCTAssertNotNil(eventsMapper.errorEventMapper)
        XCTAssertNotNil(eventsMapper.longTaskEventMapper)
    }

    func testWhenEnabledWithNoEventMappers() throws {
        // Given
        config.viewEventMapper = nil
        config.resourceEventMapper = nil
        config.actionEventMapper = nil
        config.errorEventMapper = nil
        config.longTaskEventMapper = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let eventsMapper = monitor.applicationScope.dependencies.eventBuilder.eventsMapper
        XCTAssertNil(eventsMapper.viewEventMapper)
        XCTAssertNil(eventsMapper.resourceEventMapper)
        XCTAssertNil(eventsMapper.actionEventMapper)
        XCTAssertNil(eventsMapper.errorEventMapper)
        XCTAssertNil(eventsMapper.longTaskEventMapper)
    }

    func testWhenEnabledWithCustomEndpoint() throws {
        // Given
        let randomURL: URL = .mockRandom()
        config.customEndpoint = randomURL

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertEqual((rum.requestBuilder as? RequestBuilder)?.customIntakeURL, randomURL)
    }

    func testWhenEnabledWithNoCustomEndpoint() throws {
        // Given
        config.customEndpoint = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNil((rum.requestBuilder as? RequestBuilder)?.customIntakeURL)
    }

    func testWhenEnabledWithDebugSDKArgument() throws {
        // Given
        config.sessionSampleRate = .mockRandom(min: 0, max: 100)
        config.debugSDK = true

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let crashReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, 100)
        XCTAssertEqual(crashReceiver?.sessionSampler.samplingRate, 100)
    }

    func testWhenEnabledWithNoDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.sessionSampleRate = random
        config.debugSDK = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let crashReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, random)
        XCTAssertEqual(crashReceiver?.sessionSampler.samplingRate, random)
    }

    func testWhenEnabledWithDebugViewsArgument() {
        // Given
        config.debugViews = true

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core).debug)
    }

    func testWhenEnabledWithNoDebugViewsArgument() {
        // Given
        config.debugViews = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertFalse(RUMMonitor.shared(in: core).debug)
    }

    func testWhenEnabledWithOverwritingConfigurationTelemetrySampleRate() throws {
        // Given
        config._internal_mutation { $0.configurationTelemetrySampleRate = 42 }

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 42)
    }

    func testWhenEnabledWithNoOverwritingConfigurationTelemetrySampleRate() throws {
        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 20)
    }

    // MARK: - Remote Configuration

    func testWhenEnabled_itAppliesRemoteConfigurationOnTopOfInCodeConfiguration() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.trackBackgroundEvents = false
        core.remoteConfiguration = RemoteConfiguration(
            rum: .init(applicationId: .mockRandom(), trackBackgroundEvents: true)
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertTrue(monitor.applicationScope.dependencies.trackBackgroundEvents)
    }

    func testWhenEnabledWithNoRemoteConfiguration_itUsesInCodeConfiguration() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.trackBackgroundEvents = true
        core.remoteConfiguration = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertTrue(monitor.applicationScope.dependencies.trackBackgroundEvents)
    }

    func testWhenEnabledWithRemoteTrackResources_itEnablesNetworkInstrumentation() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.urlSessionTracking = nil
        core.remoteConfiguration = RemoteConfiguration(
            rum: .init(applicationId: .mockRandom(), trackResources: true)
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(
            core.get(feature: NetworkInstrumentationFeature.self),
            "Remote `trackResources` must enable `NetworkInstrumentationFeature` at enable time"
        )
    }

    func testWhenEnabledWithRemoteTrace_itEnablesNetworkInstrumentation() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.urlSessionTracking = nil
        core.remoteConfiguration = RemoteConfiguration(
            trace: .init(tracedHosts: [.init(host: "example.com", propagatorTypes: [])])
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "Remote `trace` must enable `NetworkInstrumentationFeature` at enable time"
        )
        let urlSessionHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: URLSessionRUMResourcesHandler.self)
        )
        XCTAssertEqual(urlSessionHandler.distributedTracing?.firstPartyHosts.hosts, ["example.com"])
    }

    // MARK: - Behaviour Tests

    func testWhenEnabledWithTimeseries_itSendsUsageTelemetryOnlyAfterFeatureIsRegistered() throws {
        // Given
        weak var core: SingleFeatureCoreMock<RUMFeature>?
        var featureWasRegisteredWhenTelemetryReceived: Bool?
        let receiver = FeatureMessageReceiverMock { message in
            guard case .telemetry(.usage(let usage)) = message, case .timeseries = usage.event else {
                return
            }
            featureWasRegisteredWhenTelemetryReceived = core?.get(feature: RUMFeature.self) != nil
        }
        let strongCore = SingleFeatureCoreMock<RUMFeature>(messageReceiver: receiver)
        // `TimeseriesSessionCollector` keeps a long-lived reference to its feature scope, which would otherwise
        // create a core -> feature -> collector -> scope -> core retain cycle with the default `self`-as-scope.
        strongCore.featureScopeOverride = NOPFeatureScope()
        core = strongCore
        config.timeseries = .init(collectTypes: [.memory])

        // When
        RUM.enable(with: config, in: strongCore)

        // Then
        XCTAssertEqual(featureWasRegisteredWhenTelemetryReceived, true)
    }

    func testWhenEnabled_itSetsRUMContextInCore() throws {
        let core = PassthroughCoreMock()
        let applicationID: String = .mockRandom()
        let sessionID: RUMUUID = .mockRandom()

        // When
        config = RUM.Configuration(applicationID: applicationID)
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionID)
        config.sessionSampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // Then
        let context = core.context.additionalContext(ofType: RUMCoreContext.self)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.applicationID, applicationID)
        XCTAssertEqual(context?.sessionID, sessionID.toRUMDataFormat)
        XCTAssertNotNil(context?.viewID)
        XCTAssertNil(context?.userActionID)
    }

    func testWhenEnabled_itNotifiesInitialSessionID() {
        let core = PassthroughCoreMock()

        // Given
        let expectation = self.expectation(description: "notify initial session")
        config.onSessionStart = { sessionID, isDiscarded in
            // Then
            XCTAssertTrue(sessionID.matches(regex: .uuidRegex))
            XCTAssertEqual(sessionID, sessionID.lowercased())
            expectation.fulfill()
        }

        // When
        RUM.enable(with: config, in: core)

        waitForExpectations(timeout: 2.5)
    }

    // MARK: - RUM+Internal tests

    func testWhenPassedNOPCore_lateEnableUrlSessionTrackingThrows() {
        // Given
        let core = NOPDatadogCore()
        let config = RUM.Configuration.URLSessionTracking()

        // When + Then
        XCTAssertThrowsError(try RUM._internal.enableURLSessionTracking(with: config, in: core))
    }

    func testWhenRumNotEnabled_lateEnableUrlSessionTrackingThrows() {
        // Given
        let core = PassthroughCoreMock()
        let config = RUM.Configuration.URLSessionTracking()

        // When + Then
        XCTAssertThrowsError(try RUM._internal.enableURLSessionTracking(with: config, in: core))
    }

    func testLateEnableUrlSessionTracking() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let debugSDK: Bool = .mockRandom()
        var rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.debugSDK = debugSDK
        RUM.enable(with: rumConfig, in: core)
        let hosts: Set<String> = ["datadoghq.com", "example.com", "localhost"]
        let sampleRate: Float = .mockRandom(min: 0.0, max: 1.0)
        let hostsTracing: RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing = .trace(hosts: hosts, sampleRate: sampleRate)

        let config = RUM.Configuration.URLSessionTracking(
            firstPartyHostsTracing: hostsTracing
        )

        // When
        try RUM._internal.enableURLSessionTracking(with: config, in: core)

        // Then
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let urlSessionHandler = try XCTUnwrap(feature.handlers.first as? URLSessionRUMResourcesHandler)
        XCTAssertEqual(urlSessionHandler.distributedTracing?.firstPartyHosts.hosts, hosts)
        XCTAssertEqual(urlSessionHandler.distributedTracing?.samplingRate, debugSDK ? 100.0 : sampleRate)
    }
}

private final class MutableSceneManifestBundle: Bundle, @unchecked Sendable {
    var sceneManifest: Any?
    private(set) var sceneManifestReads = 0

    override func object(forInfoDictionaryKey key: String) -> Any? {
        guard key == "UIApplicationSceneManifest" else {
            return super.object(forInfoDictionaryKey: key)
        }
        sceneManifestReads += 1
        return sceneManifest
    }
}

private final class HandoffActivationCoreMock: DatadogCoreProtocol, RUMContextHandoffActivating {
    private let registry = FeatureRegistrationCoreMock()
    private var activeOwner: RUMContextHandoff.Owner?
    var issuedOwners: [RUMContextHandoff.Owner] = []
    var activations = 0
    var rollbacks = 0
    var ownerBoundRegistrations = 0
    var ownerReads = 0
    var rumScopeObservedActiveOwner = false
    var rumScopeOverride: FeatureScope?
    var rejectedFeatureName: String?
    var remoteConfiguration: RemoteConfiguration? { nil }

    var rumContextHandoffOwner: RUMContextHandoff.Owner? {
        ownerReads += 1
        return activeOwner
    }

    func activateRUMContextHandoff() throws -> RUMContextHandoff.Owner {
        guard activeOwner == nil else {
            throw ProgrammerError(description: "Already active")
        }
        activations += 1
        let owner = RUMContextHandoff.Owner()
        issuedOwners.append(owner)
        activeOwner = owner
        return owner
    }

    func deactivateRUMContextHandoff(owner: RUMContextHandoff.Owner) {
        guard activeOwner === owner else {
            return
        }
        rollbacks += 1
        owner.invalidate()
        activeOwner = nil
    }

    func registerRUMContextHandoff<T>(feature: T, owner: RUMContextHandoff.Owner) throws where T: DatadogFeature {
        ownerBoundRegistrations += 1
        guard activeOwner === owner, owner.isValid else {
            throw ProgrammerError(description: "Expired owner")
        }
        try register(feature: feature)
    }

    func register<T>(feature: T) throws where T: DatadogFeature {
        if T.name == rejectedFeatureName {
            throw ProgrammerError(description: "Registration rejected")
        }
        try registry.register(feature: feature)
    }

    func feature<T>(named name: String, type: T.Type) -> T? { registry.feature(named: name, type: type) }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        if T.name == RUMFeature.name {
            rumScopeObservedActiveOwner = activeOwner?.isValid == true
            return HandoffFeatureScope(base: rumScopeOverride ?? NOPFeatureScope()) { [weak self] in self?.rumContextHandoffOwner }
        }
        return NOPFeatureScope()
    }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {}
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {}
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
}

private final class HandoffFeatureScope: FeatureScope, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    private let base: FeatureScope
    private let ownerProvider: () -> RUMContextHandoff.Owner?
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { ownerProvider() }
    init(base: FeatureScope = NOPFeatureScope(), ownerProvider: @escaping () -> RUMContextHandoff.Owner?) {
        self.base = base
        self.ownerProvider = ownerProvider
    }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) { base.eventWriteContext(bypassConsent: bypassConsent, block) }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
}

#if os(iOS)
@MainActor
extension RUMTests {
    func testWebViewContextCapability_resolvesOnlyRequestedScene() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_000))
        let activationCore = HandoffActivationCoreMock()
        activationCore.rumScopeOverride = FeatureScopeMock(context: .mockWith(sdkInitDate: clock.now))
        var configuration = try XCTUnwrap(config)
        configuration.dateProvider = clock
        configuration.monotonicClock = DateProviderMonotonicClock(dateProvider: clock)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: configuration, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(rum.rumContextHandoffOwner)
        let a = RUMSceneIdentifier(rawValue: "a")
        let b = RUMSceneIdentifier(rawValue: "b")
        for scene in [a, b] {
            rum.monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier("shared"), name: scene.rawValue, path: scene.rawValue, globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(scene)))
        }
        let original = try XCTUnwrap(rum.monitor.rumContextSnapshot(for: .scene(a)))
        let peer = try XCTUnwrap(rum.monitor.rumContextSnapshot(for: .scene(b)))
        XCTAssertNotEqual(original.viewID, peer.viewID)
        let capture = try XCTUnwrap(rum.captureRUMContext(forSceneIdentifier: a.rawValue, owner: owner))
        XCTAssertTrue(capture.owner === owner)
        XCTAssertEqual(capture.value.sceneIdentifier, a.rawValue)
        XCTAssertEqual(capture.value.rumContext?.viewID, original.viewID)
        XCTAssertEqual(capture.value.rumContext?.sessionID, original.sessionID)
        XCTAssertNil(try XCTUnwrap(rum.captureRUMContext(forSceneIdentifier: "unknown", owner: owner)).value.rumContext)
        XCTAssertNil(rum.captureRUMContext(forSceneIdentifier: a.rawValue, owner: RUMContextHandoff.Owner()))
        clock.now = clock.now.addingTimeInterval(901)
        XCTAssertNil(try XCTUnwrap(rum.captureRUMContext(forSceneIdentifier: a.rawValue, owner: owner)).value.rumContext)
        owner.invalidate()
        XCTAssertNil(rum.captureRUMContext(forSceneIdentifier: a.rawValue, owner: owner))
    }

    func testWebViewContextCapability_resolvedOffDoesNotReadOwner() throws {
        let activationCore = HandoffActivationCoreMock()
        var configuration = try XCTUnwrap(config)
        configuration.featureFlags = [.multiSceneTracking: false]
        try RUM.enableOrThrow(with: configuration, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        let reads = activationCore.ownerReads
        XCTAssertNil(rum.captureRUMContext(forSceneIdentifier: "unproved", owner: RUMContextHandoff.Owner()))
        XCTAssertEqual(activationCore.ownerReads, reads)
        XCTAssertNil(rum.rumContextHandoffOwner)
        XCTAssertEqual(activationCore.activations, 0)
    }

    func testCapturedWebViewSession_actualFeatureKeepsOriginalViewWithoutActiveView() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_000))
        let activationCore = HandoffActivationCoreMock()
        activationCore.rumScopeOverride = FeatureScopeMock(context: .mockWith(sdkInitDate: clock.now))
        var configuration = try XCTUnwrap(config)
        configuration.dateProvider = clock
        configuration.monotonicClock = DateProviderMonotonicClock(dateProvider: clock)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: configuration, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(rum.rumContextHandoffOwner)
        let scene = RUMSceneIdentifier(rawValue: "owned")
        rum.monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier("a"), name: "a", path: "a", globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(scene)))
        let original = try XCTUnwrap(rum.monitor.rumContextSnapshot(for: .scene(scene)))
        let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: original, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil))
        let message = WebViewMessageWithRUMContext(message: .rum([:]), capture: capture)
        var stop = RUMStopViewCommand(time: clock.now, globalAttributes: [:], attributes: [:], identity: ViewIdentifier("a"))
        stop.target = .scene(scene)
        rum.monitor.process(command: stop)
        XCTAssertNil(rum.monitor.rumContextSnapshot(for: .scene(scene)))
        let live = try XCTUnwrap(rum.monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNil(live.viewID)
        XCTAssertEqual(live.sessionID, original.sessionID)
        XCTAssertTrue(rum.isRUMContextHandoffSessionActive(sessionID: original.sessionID, owner: owner))
        XCTAssertEqual(message.rumContext(in: activationCore, sessionID: original.sessionID)?.viewID, original.viewID)
        XCTAssertFalse(rum.isRUMContextHandoffSessionActive(sessionID: original.sessionID, owner: RUMContextHandoff.Owner()))
        owner.invalidate()
        XCTAssertFalse(rum.isRUMContextHandoffSessionActive(sessionID: original.sessionID, owner: owner))
        XCTAssertNil(message.rumContext(in: activationCore, sessionID: original.sessionID))
    }

    func testCapturedWebViewSession_actualFeatureRejectsStaleSameIDAfterExpiry() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        for maximumDuration in [false, true] {
            let start = Date(timeIntervalSince1970: 1_000)
            let clock = DateProviderMock(now: start)
            let activationCore = HandoffActivationCoreMock()
            activationCore.rumScopeOverride = FeatureScopeMock(context: .mockWith(sdkInitDate: clock.now))
            var configuration = try XCTUnwrap(config)
            configuration.dateProvider = clock
            configuration.monotonicClock = DateProviderMonotonicClock(dateProvider: clock)
            configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
            configuration.featureFlags = [.multiSceneTracking: true]
            try RUM.enableOrThrow(with: configuration, in: activationCore)
            let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
            let owner = try XCTUnwrap(rum.rumContextHandoffOwner)
            let scene = RUMSceneIdentifier(rawValue: "owned")
            rum.monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier("a"), name: "a", path: "a", globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(scene)))
            let original = try XCTUnwrap(rum.monitor.rumContextSnapshot(for: .scene(scene)))
            let message = WebViewMessageWithRUMContext(message: .rum([:]), capture: .init(owner: owner, value: .init(rumContext: original, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil)))
            XCTAssertNotNil(message.rumContext(in: activationCore, sessionID: original.sessionID))
            if maximumDuration {
                for seconds in stride(from: 600, through: 13_800, by: 600) {
                    clock.now = start.addingTimeInterval(TimeInterval(seconds))
                    rum.monitor.process(command: RUMAddUserActionCommand(target: .scene(scene), time: clock.now, attributes: [:], instrumentation: .manual, actionType: .custom, name: "keep-session-active"))
                    XCTAssertTrue(rum.isRUMContextHandoffSessionActive(sessionID: original.sessionID, owner: owner))
                }
            }
            clock.now = start.addingTimeInterval(maximumDuration ? 14_401 : 901)
            let session = try XCTUnwrap(rum.monitor.applicationScope.activeSession)
            XCTAssertEqual(session.sessionUUID.toRUMDataFormat, original.sessionID)
            if maximumDuration {
                XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: clock.now.timeIntervalSinceReferenceDate))
                XCTAssertTrue(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: clock.now.timeIntervalSinceReferenceDate))
            } else {
                XCTAssertTrue(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: clock.now.timeIntervalSinceReferenceDate))
                XCTAssertFalse(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: clock.now.timeIntervalSinceReferenceDate))
            }
            XCTAssertFalse(rum.isRUMContextHandoffSessionActive(sessionID: original.sessionID, owner: owner))
            XCTAssertNil(message.rumContext(in: activationCore, sessionID: original.sessionID))
            XCTAssertEqual(rum.monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat, original.sessionID)
            XCTAssertNil(session.endReason)
        }
    }

    func testCapturedWebViewSession_resolvedOffDoesNotReadOwner() throws {
        let activationCore = HandoffActivationCoreMock()
        var configuration = try XCTUnwrap(config)
        configuration.featureFlags = [.multiSceneTracking: false]
        try RUM.enableOrThrow(with: configuration, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        let reads = activationCore.ownerReads
        XCTAssertFalse(rum.isRUMContextHandoffSessionActive(sessionID: "unknown", owner: RUMContextHandoff.Owner()))
        XCTAssertEqual(activationCore.ownerReads, reads)
        XCTAssertNil(rum.rumContextHandoffOwner)
        XCTAssertEqual(activationCore.activations, 0)
    }

    func testAutomaticInput_resolvedOnWiresExactMonitorExecutionOwner() throws {
        let activationCore = HandoffActivationCoreMock()
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: config, in: activationCore)
        let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
        if #available(iOS 27.0, *) {
            let owner = try XCTUnwrap(rum.rumContextHandoffOwner)
            XCTAssertTrue(rum.instrumentation.actionsHandler is RUMSceneActionsHandler)
            let value = RUMContextHandoff.CurrentValue(rumContext: nil, sceneIdentifier: "owned", hasPendingUserAction: true, excludedUserActionID: "prior")
            let beforeReads = activationCore.ownerReads
            RUMContextHandoff.withValue(value, for: owner) {
                XCTAssertEqual(rum.monitor.currentExecutionContext?.sceneIdentifier, "owned")
                XCTAssertEqual(rum.monitor.currentExecutionContext?.excludedUserActionID, "prior")
                XCTAssertEqual(rum.monitor.currentExecutionContext?.hasPendingUserAction, true)
            }
            XCTAssertGreaterThan(activationCore.ownerReads, beforeReads)
            RUMContextHandoff.withValue(value, for: RUMContextHandoff.Owner()) {
                XCTAssertNil(rum.monitor.currentExecutionContext)
            }
            owner.invalidate()
            RUMContextHandoff.withValue(value, for: owner) { XCTAssertNil(rum.monitor.currentExecutionContext) }
        } else {
            XCTAssertTrue(rum.instrumentation.actionsHandler is RUMActionsHandler)
            XCTAssertNil(rum.monitor.currentExecutionContext)
            XCTAssertEqual(activationCore.activations, 0)
        }
    }

    func testAutomaticInput_defaultAndExplicitOffNeverReadHandoffOwnerDuringDispatch() throws {
        for flags: RUM.Configuration.FeatureFlags in [[:], [.multiSceneTracking: false]] {
            let activationCore = HandoffActivationCoreMock()
            config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
            config.featureFlags = flags
            let predicate = CountingAutomaticInputPredicate()
            config.uiKitActionsPredicate = predicate
            try RUM.enableOrThrow(with: config, in: activationCore)
            let rum = try XCTUnwrap(activationCore.get(feature: RUMFeature.self))
            XCTAssertTrue(rum.instrumentation.actionsHandler is RUMActionsHandler)
            let window = UIWindow(frame: .zero)
            let view = UIButton()
            window.addSubview(view)
            let event = UIEvent.mockWith(touch: UITouchMock(phase: .ended, view: view))
            let beforeReads = activationCore.ownerReads
            rum.instrumentation.actionsHandler.notify_sendEvent(application: .shared, event: event)
            XCTAssertEqual(predicate.calls, 1)
            XCTAssertNil(rum.monitor.currentExecutionContext)
            XCTAssertEqual(activationCore.ownerReads, beforeReads)
            XCTAssertEqual(activationCore.activations, 0)
        }
    }

    func testAutomaticInput_customCoreWithoutOwnerKeepsLegacyHandler() throws {
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        try RUM.enableOrThrow(with: config, in: core)
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNil(rum.rumContextHandoffOwner)
        XCTAssertTrue(rum.instrumentation.actionsHandler is RUMActionsHandler)
        XCTAssertNil(rum.monitor.currentExecutionContext)
    }
}
private final class CountingAutomaticInputPredicate: UITouchRUMActionsPredicate {
    var calls = 0
    func rumAction(targetView: UIView) -> RUMAction? {
        calls += 1
        return RUMAction(name: "selected")
    }
}
#endif
